import { Module } from '@nestjs/common';
import { CustodyService } from './custody.service.js';
import { CustodyController } from './custody.controller.js';
import { DatabaseModule } from '../../database/database.module.js';

@Module({
  imports: [DatabaseModule],
  controllers: [CustodyController],
  providers: [CustodyService],
  exports: [CustodyService],
})
export class CustodyModule {}