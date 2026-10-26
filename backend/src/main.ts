import 'dotenv/config';
import 'reflect-metadata';
import { createApp } from './app.factory';
import { loadConfig } from './common/config';

async function bootstrap(): Promise<void> {
  const app = await createApp();
  app.enableShutdownHooks();
  const { port } = loadConfig();
  await app.listen(port, '0.0.0.0');
}

void bootstrap();
