import { Module } from '@nestjs/common';
import { WalletService } from './wallet.service.js';
import { WalletController } from './wallet.controller.js';
import { DatabaseModule } from '../../database/database.module.js';

@Module({
  imports: [DatabaseModule],
  controllers: [WalletController],
  providers: [WalletService],
  exports: [WalletService],
})
export class WalletModule {}