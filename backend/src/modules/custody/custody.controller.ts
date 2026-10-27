import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  Req,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { CustodyService } from './custody.service.js';
import type { InitiateTransferDto } from './custody.service.js';
import { PrismaService } from '../../database/prisma.service.js';
import { Roles } from '../auth/roles.decorator.js';

@Controller('custody')
@Roles('MANAGER', 'EMPLOYEE', 'SUITE_ADMIN')
export class CustodyController {
  constructor(
    private readonly custodyService: CustodyService,
    private readonly prisma: PrismaService,
  ) {}

  /**
   * POST /custody/transfers
   * Initiate a custody transfer (status: pending).
   */
  @Post('transfers')
  @Roles('MANAGER', 'EMPLOYEE', 'SUITE_ADMIN')
  @HttpCode(HttpStatus.CREATED)
  async initiateTransfer(@Body() dto: InitiateTransferDto) {
    return this.custodyService.initiateTransfer(dto);
  }

  /**
   * POST /custody/transfers/:id/confirm
   * POST /custody/transfers/:id/accept
   * POST /custody/handovers/:id/accept
   * Receiver confirms acceptance.
   */
  @Post('transfers/:id/confirm')
  @Post('transfers/:id/accept')
  @Post('handovers/:id/accept')
  @Post('handovers/:id/confirm')
  @Roles('MANAGER', 'EMPLOYEE', 'SUITE_ADMIN')
  @HttpCode(HttpStatus.OK)
  async confirmTransfer(
    @Param('id') id: string,
    @Body() body?: { toWalletId?: string; destinationWalletId?: string },
    @Req() req?: any,
  ) {
    return this.custodyService.confirmTransfer(
      id,
      req?.user,
      body?.destinationWalletId || body?.toWalletId,
    );
  }

  /**
   * POST /custody/transfers/:id/dispute
   * Receiver flags discrepancy.
   */
  @Post('transfers/:id/dispute')
  @Roles('MANAGER', 'EMPLOYEE', 'SUITE_ADMIN')
  @HttpCode(HttpStatus.OK)
  async disputeTransfer(@Param('id') id: string) {
    return this.custodyService.disputeTransfer(id);
  }

  @Post('transfers/:id/cancel')
  @Roles('MANAGER', 'EMPLOYEE', 'SUITE_ADMIN')
  async cancelTransfer(@Param('id') id: string, @Req() req: any) {
    return this.custodyService.cancelTransfer(id, req?.user);
  }

  @Post('transfers/:id/decline')
  @Roles('MANAGER', 'EMPLOYEE', 'SUITE_ADMIN')
  async declineTransfer(@Param('id') id: string, @Req() req: any) {
    return this.custodyService.declineTransfer(id, req?.user);
  }

  /**
   * GET /custody/transfers?custodianId=...
   * Returns all custody transfers involving this custodian (incoming and outgoing).
   */
  @Get('transfers')
  @Roles('MANAGER', 'EMPLOYEE', 'SUITE_ADMIN')
  async getTransfers(@Query() query: any) {
    try {
      return await this.custodyService.getTransfers(query?.custodianId);
    } catch (err) {
      console.error('[CUSTODY CONTROLLER] getTransfers error:', err);
      return [];
    }
  }

  /**
   * GET /custody/notifications?custodianId=...&companyId=...
   * Returns pending handover requests and recent movement activity.
   */
  @Get('notifications')
  @Roles('MANAGER', 'EMPLOYEE', 'SUITE_ADMIN')
  async getNotifications(
    @Query('custodianId') custodianId: string,
    @Query('companyId') companyId: string,
  ) {
    return this.custodyService.getNotifications(custodianId, companyId);
  }

  /**
   * GET /custody/transfers/pending
   */
  @Get('transfers/pending')
  @Roles('MANAGER', 'EMPLOYEE', 'SUITE_ADMIN')
  async getPendingTransfers(@Req() req: any) {
    return this.custodyService.getPendingTransfers(req?.user);
  }

  /**
   * GET /custody/custodians
   * List all custodians for the company.
   */
  @Get('custodians')
  @Roles('MANAGER', 'EMPLOYEE', 'SUITE_ADMIN')
  async getCustodians(@Query('companyId') companyId: string) {
    return this.custodyService.getCustodians(companyId);
  }

  /**
   * GET /custody/wallets
   * List all wallets for the logged-in user or custodian.
   */
  @Get('wallets')
  @Roles('MANAGER', 'EMPLOYEE', 'SUITE_ADMIN')
  async getWallets(
    @Query('custodianId') queryCustodianId?: string,
    @Query('companyId') queryCompanyId?: string,
    @Req() req?: any,
  ) {
    const identifier =
      queryCustodianId ||
      req?.user?.id ||
      req?.user?.userId ||
      req?.user?.custodianId ||
      req?.user?.sub;
    return this.custodyService.getCustodianWallets(identifier, queryCompanyId);
  }

  /**
   * GET /custody/custodians/:id/wallets
   */
  @Get('custodians/:id/wallets')
  @Roles('MANAGER', 'EMPLOYEE', 'SUITE_ADMIN')
  async getCustodianWalletsById(
    @Param('id') id: string,
    @Query('companyId') queryCompanyId?: string,
  ) {
    return this.custodyService.getCustodianWallets(id, queryCompanyId);
  }
}
