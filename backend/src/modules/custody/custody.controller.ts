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

@Controller('custody')
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
  @HttpCode(HttpStatus.CREATED)
  async initiateTransfer(@Body() dto: InitiateTransferDto) {
    return this.custodyService.initiateTransfer(dto);
  }

  /**
   * POST /custody/transfers/:id/confirm
   * Receiver confirms acceptance.
   */
  @Post('transfers/:id/confirm')
  @HttpCode(HttpStatus.OK)
  async confirmTransfer(
    @Param('id') id: string,
    @Req() req?: any,
  ) {
    return this.custodyService.confirmTransfer(id, req?.user);
  }

  /**
   * POST /custody/transfers/:id/dispute
   * Receiver flags discrepancy.
   */
  @Post('transfers/:id/dispute')
  @HttpCode(HttpStatus.OK)
  async disputeTransfer(@Param('id') id: string) {
    return this.custodyService.disputeTransfer(id);
  }

  @Post('transfers/:id/cancel')
  async cancelTransfer(@Param('id') id: string, @Req() req: any) {
    return this.custodyService.cancelTransfer(id, req.user);
  }

  @Post('transfers/:id/decline')
  async declineTransfer(@Param('id') id: string, @Req() req: any) {
    return this.custodyService.declineTransfer(id, req.user);
  }

  /**
   * GET /custody/transfers?custodianId=...
   * Returns all custody transfers involving this custodian (incoming and outgoing).
   */
  @Get('transfers')
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
  async getPendingTransfers(@Req() req: any) {
    return this.custodyService.getPendingTransfers(req?.user);
  }

  /**
   * GET /custody/custodians
   * List all custodians for the company.
   */
  @Get('custodians')
  async getCustodians(@Query('companyId') companyId: string) {
    return this.custodyService.getCustodians(companyId);
  }
}
