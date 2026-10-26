import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Role, Shop, User } from '@prisma/client';
import { compare, hash } from 'bcryptjs';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { AccessTokenPayload, AuthUser } from '../../common/auth/auth-user';
import { currencySymbol } from '../../common/currencies';
import { DomainConflict } from '../../common/errors';
import { PrismaService } from '../../common/prisma.service';
import { ChangePasswordDto, LoginDto, SignupDto } from './dto';

export const ACCESS_TTL_SECONDS = 15 * 60;
export const REFRESH_TTL_SECONDS = 30 * 24 * 60 * 60;
const BCRYPT_ROUNDS = 12;

export interface Session {
  user: PublicUser;
  shop: PublicShop;
  accessToken: string;
  refreshToken: string;
  accessExpiresIn: number;
}

export interface PublicUser {
  id: string;
  email: string;
  name: string;
  role: 'owner' | 'cashier';
}

export interface PublicShop {
  id: string;
  name: string;
  currency: string;
  currencySymbol: string;
}

export function publicUser(u: Pick<User, 'id' | 'email' | 'name' | 'role'>): PublicUser {
  return { id: u.id, email: u.email, name: u.name, role: u.role === Role.OWNER ? 'owner' : 'cashier' };
}

export function publicShop(s: Shop): PublicShop {
  return { id: s.id, name: s.name, currency: s.currency, currencySymbol: s.currencySymbol };
}

export function hashPassword(password: string): Promise<string> {
  return hash(password, BCRYPT_ROUNDS);
}

function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

// Compared against when the email is unknown, so response time does not
// reveal which emails have accounts.
let dummyHash: Promise<string> | undefined;
function getDummyHash(): Promise<string> {
  dummyHash ??= hash(randomBytes(16).toString('hex'), BCRYPT_ROUNDS);
  return dummyHash;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
  ) {}

  /** Creates a shop with its owner account and signs the owner in. */
  async signup(dto: SignupDto, userAgent?: string): Promise<Session> {
    const existing = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (existing) throw new DomainConflict('email_taken', 'An account with this email already exists');
    const passwordHash = await hashPassword(dto.password);
    const { user, shop } = await this.prisma.$transaction(async (tx) => {
      const shop = await tx.shop.create({
        data: { name: dto.shopName, currency: dto.currency, currencySymbol: currencySymbol(dto.currency) ?? '₹' },
      });
      const user = await tx.user.create({
        data: { shopId: shop.id, email: dto.email, name: dto.name, passwordHash, role: Role.OWNER },
      });
      return { user, shop };
    });
    return this.issue(user, shop, randomUUID(), userAgent);
  }

  async login(dto: LoginDto, userAgent?: string): Promise<Session> {
    const user = await this.prisma.user.findUnique({ where: { email: dto.email }, include: { shop: true } });
    const ok = await compare(dto.password, user?.passwordHash ?? (await getDummyHash()));
    if (!user || !ok) throw new UnauthorizedException('Incorrect email or password');
    if (!user.isActive) throw new UnauthorizedException('This account has been disabled by the shop owner');
    return this.issue(user, user.shop, randomUUID(), userAgent);
  }

  /**
   * Rotates a refresh token. Presenting a token that was already rotated
   * means it was copied, so the whole login (family) is revoked.
   */
  async refresh(token: string | undefined, userAgent?: string): Promise<Session> {
    if (!token) throw new UnauthorizedException('Please sign in');
    const record = await this.prisma.refreshToken.findUnique({
      where: { tokenHash: hashToken(token) },
      include: { user: { include: { shop: true } } },
    });
    if (!record) throw new UnauthorizedException('Please sign in');
    if (record.revokedAt) {
      await this.revokeFamily(record.family);
      throw new UnauthorizedException('Please sign in');
    }
    if (record.expiresAt <= new Date() || !record.user.isActive) {
      throw new UnauthorizedException('Please sign in');
    }
    // Only one concurrent refresh can win the rotation.
    const rotated = await this.prisma.refreshToken.updateMany({
      where: { id: record.id, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    if (rotated.count !== 1) throw new UnauthorizedException('Please sign in');
    return this.issue(record.user, record.user.shop, record.family, userAgent);
  }

  async logout(token: string | undefined): Promise<void> {
    if (!token) return;
    await this.prisma.refreshToken.updateMany({
      where: { tokenHash: hashToken(token), revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  async me(user: AuthUser): Promise<{ user: PublicUser; shop: PublicShop }> {
    const shop = await this.prisma.shop.findUniqueOrThrow({ where: { id: user.shopId } });
    return { user: publicUser(user), shop: publicShop(shop) };
  }

  /** Changes the password and signs out every other session. */
  async changePassword(auth: AuthUser, dto: ChangePasswordDto, userAgent?: string): Promise<Session> {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: auth.id }, include: { shop: true } });
    if (!(await compare(dto.currentPassword, user.passwordHash))) {
      throw new UnauthorizedException('Current password is incorrect');
    }
    const passwordHash = await hashPassword(dto.newPassword);
    await this.prisma.$transaction([
      this.prisma.user.update({ where: { id: user.id }, data: { passwordHash } }),
      this.prisma.refreshToken.updateMany({
        where: { userId: user.id, revokedAt: null },
        data: { revokedAt: new Date() },
      }),
    ]);
    return this.issue(user, user.shop, randomUUID(), userAgent);
  }

  async revokeAllForUser(userId: string): Promise<void> {
    await this.prisma.refreshToken.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date() } });
  }

  private async revokeFamily(family: string): Promise<void> {
    await this.prisma.refreshToken.updateMany({ where: { family, revokedAt: null }, data: { revokedAt: new Date() } });
  }

  private async issue(user: User, shop: Shop, family: string, userAgent?: string): Promise<Session> {
    const payload: AccessTokenPayload = { sub: user.id, shop: user.shopId };
    const accessToken = await this.jwt.signAsync(payload, { expiresIn: ACCESS_TTL_SECONDS });
    const refreshToken = randomBytes(48).toString('base64url');
    await this.prisma.refreshToken.create({
      data: {
        userId: user.id,
        family,
        tokenHash: hashToken(refreshToken),
        expiresAt: new Date(Date.now() + REFRESH_TTL_SECONDS * 1000),
        userAgent: userAgent?.slice(0, 300),
      },
    });
    return {
      user: publicUser(user),
      shop: publicShop(shop),
      accessToken,
      refreshToken,
      accessExpiresIn: ACCESS_TTL_SECONDS,
    };
  }
}
