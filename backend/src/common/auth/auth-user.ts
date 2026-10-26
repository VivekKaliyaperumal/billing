import { Role } from '@prisma/client';

/** The signed-in user, loaded fresh on every request by the AuthGuard. */
export interface AuthUser {
  id: string;
  shopId: string;
  role: Role;
  email: string;
  name: string;
}

export interface AccessTokenPayload {
  sub: string;
  shop: string;
}
