import { Module } from '@nestjs/common';
import { ManagerService } from './manager.service.js';
import { ManagerController } from './manager.controller.js';
import { DatabaseModule } from '../../database/database.module.js';

@Module({
  imports: [DatabaseModule],
  controllers: [ManagerController],
  providers: [ManagerService],
  exports: [ManagerService],
})
export class ManagerModule {}
