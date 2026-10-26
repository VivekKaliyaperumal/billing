import { createParamDecorator, ExecutionContext, SetMetadata } from '@nestjs/common';
import { Role } from '@prisma/client';
import { FastifyRequest } from 'fastify';
import { AuthUser } from './auth-user';

export const IS_PUBLIC = 'isPublic';
export const ROLES = 'roles';

/** Skips authentication (signup, login, refresh, health). */
export const Public = () => SetMetadata(IS_PUBLIC, true);

/** Restricts a route to the given roles. */
export const Roles = (...roles: Role[]) => SetMetadata(ROLES, roles);

export const OwnerOnly = () => Roles(Role.OWNER);

export type AuthedRequest = FastifyRequest & { user: AuthUser };

export const CurrentUser = createParamDecorator(
  (_: unknown, ctx: ExecutionContext): AuthUser => ctx.switchToHttp().getRequest<AuthedRequest>().user,
);
