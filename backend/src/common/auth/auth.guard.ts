import { CanActivate, ExecutionContext, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { Role } from '@prisma/client';
import { FastifyRequest } from 'fastify';
import { PrismaService } from '../prisma.service';
import { AccessTokenPayload } from './auth-user';
import { ACCESS_COOKIE, CSRF_HEADER } from './cookies';
import { AuthedRequest, IS_PUBLIC, ROLES } from './decorators';

const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

/**
 * Global guard. Accepts a Bearer token (mobile) or the access cookie (web).
 * Cookie-authenticated writes must carry X-Requested-With, which blocks
 * cross-site form posts. The user is re-read from the database so a
 * deactivated user or a role change takes effect immediately.
 */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly jwt: JwtService,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const targets = [context.getHandler(), context.getClass()];
    if (this.reflector.getAllAndOverride<boolean>(IS_PUBLIC, targets)) return true;

    const req = context.switchToHttp().getRequest<AuthedRequest>();
    const { token, fromCookie } = extractToken(req);
    if (!token) throw new UnauthorizedException('Please sign in');
    if (fromCookie && !SAFE_METHODS.has(req.method) && !req.headers[CSRF_HEADER]) {
      throw new ForbiddenException('Missing X-Requested-With header');
    }

    let payload: AccessTokenPayload;
    try {
      payload = await this.jwt.verifyAsync<AccessTokenPayload>(token);
    } catch {
      throw new UnauthorizedException('Session expired');
    }
    const user = await this.prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user || !user.isActive || user.shopId !== payload.shop) {
      throw new UnauthorizedException('Session expired');
    }
    req.user = { id: user.id, shopId: user.shopId, role: user.role, email: user.email, name: user.name };

    const roles = this.reflector.getAllAndOverride<Role[] | undefined>(ROLES, targets);
    if (roles && !roles.includes(user.role)) {
      throw new ForbiddenException('Only the shop owner can do this');
    }
    return true;
  }
}

function extractToken(req: FastifyRequest): { token?: string; fromCookie: boolean } {
  const header = req.headers.authorization;
  if (header?.startsWith('Bearer ')) return { token: header.slice(7), fromCookie: false };
  const cookie = req.cookies?.[ACCESS_COOKIE];
  return { token: cookie, fromCookie: Boolean(cookie) };
}
