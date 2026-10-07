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
  ForbiddenException,
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
   * Receiver confirms acceptance. Any authenticated custodian who is the
   * designated to_custodian_id may confirm (not restricted to accounts role).
   */
  @Post('transfers/:id/confirm')
  @HttpCode(HttpStatus.OK)
  async confirmTransfer(
    @Param('id') id: string,
    @Body('toWalletId') toWalletId?: string,
    @Req() req?: { user?: { id: string; role: string; companyIds: string[] } },
  ) {
    // Fetch the transfer with its sender custodian to get companyId
    const transfer = await this.custodyService['prisma'].custodyTransfer.findUnique({
      where: { id },
      include: { fromCustodian: { select: { companyId: true } } },
    });
    if (!transfer) {
      // Let the service handle the "not found" error
      return this.custodyService.confirmTransfer(id, toWalletId);
    }

    // Look up the caller's custodian account within the transfer's company
    if (req?.user?.id) {
      const callerCustodian = await this.prisma.custodianAccount.findFirst({
        where: {
          linkedUserId: req.user.id,
          companyId: transfer.fromCustodian.companyId,
        },
      });

      if (!callerCustodian || callerCustodian.id !== transfer.toCustodianId) {
        throw new ForbiddenException(
          'Only the designated receiver custodian can confirm this transfer',
        );
      }
    }

    return this.custodyService.confirmTransfer(id, toWalletId);
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
  async getPendingTransfers(@Req() req: any, @Query('custodianId') queryCustodianId?: string) {
    const custodianId = queryCustodianId || req?.user?.custodianId;
    return this.custodyService.getPendingTransfers(custodianId, req?.user);
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