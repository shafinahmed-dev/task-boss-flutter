import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { AppController } from './app.controller.js';
import { AppService } from './app.service.js';
import { DatabaseModule } from './database/database.module.js';
import { LedgerModule } from './modules/ledger/ledger.module.js';
import { CustodyModule } from './modules/custody/custody.module.js';
import { ReceiptModule } from './modules/receipt/receipt.module.js';
import { WalletModule } from './modules/wallet/wallet.module.js';
import { AuthModule } from './modules/auth/auth.module.js';
import { SuiteModule } from './modules/suite/suite.module.js';
import { ManagerModule } from './modules/manager/manager.module.js';
import { JwtAuthGuard } from './modules/auth/jwt-auth.guard.js';
import { RolesGuard } from './modules/auth/roles.guard.js';
import { CompanyScopeGuard } from './modules/auth/company-scope.guard.js';

@Module({
  imports: [DatabaseModule, AuthModule, LedgerModule, CustodyModule, ReceiptModule, WalletModule, SuiteModule, ManagerModule],
  controllers: [AppController],
  providers: [
    AppService,
    // Global guards — applied to all routes by default.
    // JwtAuthGuard is applied first (skip on @Public() routes).
    // RolesGuard checks role hierarchy.
    // CompanyScopeGuard enforces multi-entity isolation.
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
    { provide: APP_GUARD, useClass: CompanyScopeGuard },
  ],
})
export class AppModule {}
