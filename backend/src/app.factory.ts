import fastifyCookie from '@fastify/cookie';
import fastifyHelmet from '@fastify/helmet';
import { NestFactory } from '@nestjs/core';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { cleanupOpenApiDoc } from 'nestjs-zod';
import { AppModule } from './app.module';
import { CSRF_HEADER } from './common/auth/cookies';
import { loadConfig } from './common/config';

/** Backups can be large: the app caps a backup file at 20 MB. */
const BODY_LIMIT_BYTES = 25 * 1024 * 1024;

/** Builds the configured app; shared by main.ts and the e2e tests. */
export async function createApp(options: { logger?: boolean; docs?: boolean } = {}): Promise<NestFastifyApplication> {
  const config = loadConfig();
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    new FastifyAdapter({ bodyLimit: BODY_LIMIT_BYTES, trustProxy: true }),
    { logger: options.logger === false ? false : undefined },
  );
  app.setGlobalPrefix('api/v1');
  await app.register(fastifyCookie);
  // The API serves JSON only; the CSP would just block the Swagger page.
  await app.register(fastifyHelmet, { contentSecurityPolicy: false });
  app.enableCors({
    origin: config.corsOrigins,
    credentials: true,
    allowedHeaders: ['Content-Type', 'Authorization', CSRF_HEADER],
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
  });

  if (options.docs === false) return app;
  const doc = SwaggerModule.createDocument(
    app,
    new DocumentBuilder()
      .setTitle('Thyantra Billing API')
      .setDescription(
        'Shops, products, checkout, customer credit, reports, backup and offline sync for the web and mobile apps. ' +
          'Money is in integer minor units (paise). The web authenticates with httpOnly cookies and must send ' +
          'X-Requested-With on writes; the mobile app sends a Bearer token.',
      )
      .setVersion('1.0')
      .addBearerAuth()
      .addCookieAuth('tb_access')
      .build(),
  );
  SwaggerModule.setup('api/docs', app, cleanupOpenApiDoc(doc));
  return app;
}
