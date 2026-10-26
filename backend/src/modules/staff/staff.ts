import { Body, Controller, Delete, Get, HttpCode, Injectable, Module, Param, ParseUUIDPipe, Patch, Post } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Role } from '@prisma/client';
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';
import { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, OwnerOnly } from '../../common/auth/decorators';
import { DomainConflict, NotFound } from '../../common/errors';
import { PrismaService } from '../../common/prisma.service';
import { zName } from '../../common/validation';
import { zEmail, zPassword } from '../auth/dto';
import { AuthModule } from '../auth/module';
import { AuthService, hashPassword, publicUser } from '../auth/service';

const zRole = z.enum(['owner', 'cashier']);

export class CreateStaffDto extends createZodDto(
  z.object({ name: zName, email: zEmail, password: zPassword, role: zRole.default('cashier') }),
) {}

export class UpdateStaffDto extends createZodDto(
  z.object({
    name: zName.optional(),
    role: zRole.optional(),
    isActive: z.boolean().optional(),
    /** Owner-set password reset for a staff member. */
    password: zPassword.optional(),
  }),
) {}

function toRole(r: 'owner' | 'cashier'): Role {
  return r === 'owner' ? Role.OWNER : Role.CASHIER;
}

interface StaffMember {
  id: string;
  email: string;
  name: string;
  role: 'owner' | 'cashier';
  isActive: boolean;
  createdAt: Date;
}

@Injectable()
export class StaffService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auth: AuthService,
  ) {}

  async list(shopId: string): Promise<StaffMember[]> {
    const users = await this.prisma.user.findMany({ where: { shopId }, orderBy: { createdAt: 'asc' } });
    return users.map((u) => ({ ...publicUser(u), isActive: u.isActive, createdAt: u.createdAt }));
  }

  async create(owner: AuthUser, dto: CreateStaffDto): Promise<StaffMember> {
    if (await this.prisma.user.findUnique({ where: { email: dto.email } })) {
      throw new DomainConflict('email_taken', 'An account with this email already exists');
    }
    const u = await this.prisma.user.create({
      data: {
        shopId: owner.shopId,
        email: dto.email,
        name: dto.name,
        role: toRole(dto.role),
        passwordHash: await hashPassword(dto.password),
      },
    });
    return { ...publicUser(u), isActive: u.isActive, createdAt: u.createdAt };
  }

  async update(owner: AuthUser, id: string, dto: UpdateStaffDto): Promise<StaffMember> {
    const target = await this.find(owner, id);
    if (target.id === owner.id && (dto.isActive === false || (dto.role && dto.role !== 'owner'))) {
      throw new DomainConflict('self_lockout', 'You cannot deactivate or demote your own account');
    }
    const u = await this.prisma.user.update({
      where: { id: target.id },
      data: {
        name: dto.name,
        role: dto.role ? toRole(dto.role) : undefined,
        isActive: dto.isActive,
        passwordHash: dto.password ? await hashPassword(dto.password) : undefined,
      },
    });
    // A disabled user or a reset password ends their existing sessions.
    if (dto.isActive === false || dto.password) await this.auth.revokeAllForUser(u.id);
    return { ...publicUser(u), isActive: u.isActive, createdAt: u.createdAt };
  }

  async remove(owner: AuthUser, id: string): Promise<void> {
    const target = await this.find(owner, id);
    if (target.id === owner.id) throw new DomainConflict('self_lockout', 'You cannot delete your own account');
    // Sales keep the id in createdById; there is no foreign key to break.
    await this.prisma.user.delete({ where: { id: target.id } });
  }

  private async find(owner: AuthUser, id: string) {
    const target = await this.prisma.user.findFirst({ where: { id, shopId: owner.shopId } });
    if (!target) throw new NotFound('Staff member');
    return target;
  }
}

@ApiTags('staff')
@OwnerOnly()
@Controller('staff')
export class StaffController {
  constructor(private readonly staff: StaffService) {}

  @Get()
  list(@CurrentUser() user: AuthUser) {
    return this.staff.list(user.shopId);
  }

  @Post()
  create(@CurrentUser() user: AuthUser, @Body() dto: CreateStaffDto) {
    return this.staff.create(user, dto);
  }

  @Patch(':id')
  update(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateStaffDto) {
    return this.staff.update(user, id, dto);
  }

  @Delete(':id')
  @HttpCode(204)
  remove(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.staff.remove(user, id);
  }
}

@Module({ imports: [AuthModule], controllers: [StaffController], providers: [StaffService] })
export class StaffModule {}
