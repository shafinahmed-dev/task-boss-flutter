import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module.js';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.enableCors({
    origin: true,
    methods: 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS',
    credentials: true,
    allowedHeaders: ['Content-Type', 'Accept', 'Authorization', 'x-company-id', 'idempotency-key'],
  });

  const port = Number(process.env.PORT ?? 3000);

  // Gracefully handle EADDRINUSE: if port is taken, log clearly and exit
  // so the process manager (PM2, Docker, shell) knows to kill the old one first.
  const server = app.getHttpServer();
  server.on('error', (err: NodeJS.ErrnoException) => {
    if (err.code === 'EADDRINUSE') {
      console.error(
        `\n❌  Port ${port} is already in use.\n` +
        `   Kill the existing process first:\n` +
        `   👉  npx kill-port ${port}\n` +
        `   Then restart: npm run start:prod\n`,
      );
      process.exit(1);
    }
  });

  await app.listen(port, '0.0.0.0');
  console.log(`✅  Server running on http://0.0.0.0:${port}`);
}
await bootstrap();
