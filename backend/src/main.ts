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

  await app.listen(process.env.PORT ?? 3000, '0.0.0.0');
}
await bootstrap();