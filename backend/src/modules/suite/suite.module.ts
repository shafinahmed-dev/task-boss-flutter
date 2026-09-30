import { Module } from '@nestjs/common';
import { SuiteController } from './suite.controller.js';
import { SuiteService } from './suite.service.js';
import { DatabaseModule } from '../../database/database.module.js';

@Module({
  imports: [DatabaseModule],
  controllers: [SuiteController],
  providers: [SuiteService],
  exports: [SuiteService],
})
export class SuiteModule {}
