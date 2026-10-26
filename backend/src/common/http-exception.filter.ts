import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { FastifyReply } from 'fastify';
import { ZodValidationException } from 'nestjs-zod';
import { ZodError } from 'zod';

/**
 * One error shape for every response: { statusCode, error, code, message, ... }.
 * Validation errors list each field; unexpected errors are logged and hidden.
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger('Exceptions');

  catch(exception: unknown, host: ArgumentsHost): void {
    const reply = host.switchToHttp().getResponse<FastifyReply>();

    if (exception instanceof ZodValidationException) {
      const zodError = exception.getZodError();
      const issues =
        zodError instanceof ZodError
          ? zodError.issues.map((i) => ({ path: i.path.join('.'), message: i.message }))
          : [];
      void reply.status(400).send({
        statusCode: 400,
        error: 'Bad Request',
        code: 'validation_failed',
        message: issues[0]?.message ?? 'Invalid request',
        issues,
      });
      return;
    }

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const body = exception.getResponse();
      const payload =
        typeof body === 'string'
          ? { statusCode: status, error: exception.name, code: codeFor(status), message: body }
          : { code: codeFor(status), ...(body as Record<string, unknown>), statusCode: status };
      void reply.status(status).send(payload);
      return;
    }

    if (exception instanceof Prisma.PrismaClientKnownRequestError && exception.code === 'P2002') {
      void reply.status(409).send({
        statusCode: 409,
        error: 'Conflict',
        code: 'duplicate',
        message: 'A record with these details already exists',
      });
      return;
    }

    this.logger.error(exception instanceof Error ? exception.stack : String(exception));
    void reply.status(HttpStatus.INTERNAL_SERVER_ERROR).send({
      statusCode: 500,
      error: 'Internal Server Error',
      code: 'internal_error',
      message: 'Something went wrong. Please try again.',
    });
  }
}

function codeFor(status: number): string {
  switch (status) {
    case 400:
      return 'bad_request';
    case 401:
      return 'unauthorized';
    case 403:
      return 'forbidden';
    case 404:
      return 'not_found';
    case 409:
      return 'conflict';
    case 413:
      return 'too_large';
    case 429:
      return 'rate_limited';
    default:
      return 'error';
  }
}
