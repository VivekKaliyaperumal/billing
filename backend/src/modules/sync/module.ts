import { Body, Controller, Get, HttpCode, Module, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser } from '../../common/auth/decorators';
import { PullQuery, PushDto } from './dto';
import { SyncService } from './service';

@ApiTags('sync')
@Controller('sync')
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  /** Upload a device's queued changes. Always 200; see each op's `status`. */
  @Post('push')
  @HttpCode(200)
  push(@CurrentUser() user: AuthUser, @Body() dto: PushDto) {
    return this.sync.push(user, dto);
  }

  /** Download changes since the cursor. */
  @Get('pull')
  pull(@CurrentUser() user: AuthUser, @Query() q: PullQuery) {
    return this.sync.pull(user, q);
  }
}

@Module({ controllers: [SyncController], providers: [SyncService] })
export class SyncModule {}
