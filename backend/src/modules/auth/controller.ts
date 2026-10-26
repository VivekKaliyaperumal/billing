import { Body, Controller, Get, HttpCode, Post, Req, Res } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { FastifyReply, FastifyRequest } from 'fastify';
import { AuthUser } from '../../common/auth/auth-user';
import { ACCESS_COOKIE, REFRESH_COOKIE, REFRESH_COOKIE_PATH } from '../../common/auth/cookies';
import { CurrentUser, Public } from '../../common/auth/decorators';
import { ChangePasswordDto, LoginDto, RefreshDto, SignupDto } from './dto';
import { ACCESS_TTL_SECONDS, AuthService, REFRESH_TTL_SECONDS, Session } from './service';

/** Strict limit for credential endpoints: 10 attempts a minute per IP. */
const CREDENTIAL_LIMIT = { default: { limit: 10, ttl: 60_000 } };

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Throttle(CREDENTIAL_LIMIT)
  @Post('signup')
  async signup(@Body() dto: SignupDto, @Req() req: FastifyRequest, @Res({ passthrough: true }) res: FastifyReply) {
    return this.respond(await this.auth.signup(dto, req.headers['user-agent']), dto.client, res);
  }

  @Public()
  @Throttle(CREDENTIAL_LIMIT)
  @Post('login')
  @HttpCode(200)
  async login(@Body() dto: LoginDto, @Req() req: FastifyRequest, @Res({ passthrough: true }) res: FastifyReply) {
    return this.respond(await this.auth.login(dto, req.headers['user-agent']), dto.client, res);
  }

  @Public()
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @Post('refresh')
  @HttpCode(200)
  async refresh(@Body() dto: RefreshDto, @Req() req: FastifyRequest, @Res({ passthrough: true }) res: FastifyReply) {
    const token = dto.refreshToken ?? req.cookies[REFRESH_COOKIE];
    try {
      return this.respond(await this.auth.refresh(token, req.headers['user-agent']), dto.client, res);
    } catch (e) {
      clearCookies(res);
      throw e;
    }
  }

  @Public()
  @Post('logout')
  @HttpCode(204)
  async logout(@Body() dto: RefreshDto, @Req() req: FastifyRequest, @Res({ passthrough: true }) res: FastifyReply) {
    await this.auth.logout(dto.refreshToken ?? req.cookies[REFRESH_COOKIE]);
    clearCookies(res);
  }

  @Get('me')
  me(@CurrentUser() user: AuthUser) {
    return this.auth.me(user);
  }

  @Throttle(CREDENTIAL_LIMIT)
  @Post('change-password')
  @HttpCode(200)
  async changePassword(
    @CurrentUser() user: AuthUser,
    @Body() dto: ChangePasswordDto,
    @Req() req: FastifyRequest,
    @Res({ passthrough: true }) res: FastifyReply,
  ) {
    return this.respond(await this.auth.changePassword(user, dto, req.headers['user-agent']), dto.client, res);
  }

  /** Web: tokens go in httpOnly cookies, never in the body. Mobile: in the body. */
  private respond(session: Session, client: 'web' | 'mobile', res: FastifyReply) {
    if (client === 'mobile') return session;
    const secure = process.env.COOKIE_SECURE === 'true';
    void res.setCookie(ACCESS_COOKIE, session.accessToken, {
      httpOnly: true,
      secure,
      sameSite: 'lax',
      path: '/',
      maxAge: ACCESS_TTL_SECONDS,
    });
    void res.setCookie(REFRESH_COOKIE, session.refreshToken, {
      httpOnly: true,
      secure,
      sameSite: 'lax',
      path: REFRESH_COOKIE_PATH,
      maxAge: REFRESH_TTL_SECONDS,
    });
    return { user: session.user, shop: session.shop, accessExpiresIn: session.accessExpiresIn };
  }
}

function clearCookies(res: FastifyReply): void {
  void res.clearCookie(ACCESS_COOKIE, { path: '/' });
  void res.clearCookie(REFRESH_COOKIE, { path: REFRESH_COOKIE_PATH });
}
