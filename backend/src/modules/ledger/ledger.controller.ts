import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  HttpCode,
  HttpStatus,
  HttpException,
} from '@nestjs/common';
import { LedgerService } from './ledger.service.js';
import type {
  RecordMovementDto,
  EditMovementDto,
  InterCompanyAllocationDto,
} from './ledger.service.js';
import { Roles } from '../auth/roles.decorator.js';

@Controller('ledger')
export class LedgerController {
  constructor(private readonly ledgerService: LedgerService) {}

  /**
   * POST /ledger/movements
   * Record a new money movement. Idempotent via idempotencyKey.
   */
  @Post('movements')
  @HttpCode(HttpStatus.CREATED)
  async recordMovement(@Body() dto: RecordMovementDto) {
    console.log('--- [DEBUG] INCOMING MOVEMENT PAYLOAD ---');
    console.log(JSON.stringify(dto, null, 2));
    try {
      const result = await this.ledgerService.recordMoneyMovement(dto);
      console.log('--- [DEBUG] MOVEMENT SAVED SUCCESSFULLY ---', (result as any)?.id);
      return result;
    } catch (error: any) {
      console.error('--- [DEBUG] ERROR IN RECORD MOVEMENT ---');
      console.error('Error message:', error?.message);
      console.error('Prisma / DB error code:', error?.code);
      console.error('Full stack:', error?.stack);
      throw new HttpException(
        error?.message || 'Database error processing movement',
        error?.status || HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }

  /**
   * POST /ledger/movements/:id/edit
   * Submit an append-only correction. Creates a new movement row
   * with edited_from_id pointing to the original.
   */
  @Post('movements/:id/edit')
  @HttpCode(HttpStatus.CREATED)
  async editMovement(
    @Param('id') id: string,
    @Body() dto: EditMovementDto,
  ) {
    return this.ledgerService.editMoneyMovement(id, dto);
  }

  /**
   * GET /ledger/custodians/:id/balance?companyId=...
   * Returns the dynamically computed balance for a custodian.
   */
  @Get('custodians/:id/balance')
  async getCustodianBalance(
    @Param('id') id: string,
    @Query('companyId') companyId: string,
  ) {
    return this.ledgerService.getCustodianBalance(id, companyId);
  }

  /**
   * GET /ledger/custodians/:id/movements?page=1&limit=50&direction=in
   * Paginated ledger history for a custodian.
   */
  /**
   * POST /ledger/allocations/inter-company
   * Record a cross-entity shared cost. Creates an OUT movement under source
   * company and an offsetting inter-company liability/receivable entry.
   */
  @Post('allocations/inter-company')
  @HttpCode(HttpStatus.CREATED)
  @Roles('accounts', 'approver', 'admin')
  async allocateInterCompanyCost(
    @Body() dto: InterCompanyAllocationDto,
  ) {
    return this.ledgerService.allocateInterCompanyCost(dto);
  }

  /**
   * POST /ledger/allocations/:id/settle
   * Mark an inter-company allocation as settled.
   */
  @Post('allocations/:id/settle')
  @HttpCode(HttpStatus.OK)
  @Roles('accounts', 'approver', 'admin')
  async settleInterCompanyAllocation(@Param('id') id: string) {
    return this.ledgerService.settleInterCompanyAllocation(id);
  }

  /**
   * GET /ledger/custodians/:id/movements?page=1&limit=50&direction=in
   * Paginated ledger history for a custodian.
   */
  @Get('custodians/:id/movements')
  async getCustodianMovements(
    @Param('id') id: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Query('direction') direction?: 'in' | 'out',
  ) {
    return this.ledgerService.getCustodianMovements(id, {
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
      direction,
    });
  }
}