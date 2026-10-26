import { ConflictException, NotFoundException } from '@nestjs/common';

/** 409 with a stable `code` the clients can switch on. */
export class DomainConflict extends ConflictException {
  constructor(code: string, message: string, details?: Record<string, unknown>) {
    super({ statusCode: 409, error: 'Conflict', code, message, ...details });
  }
}

export class NotFound extends NotFoundException {
  constructor(what: string) {
    super({ statusCode: 404, error: 'Not Found', code: 'not_found', message: `${what} not found` });
  }
}
