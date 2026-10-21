import {
  Controller,
  Get,
  Post,
  Put,
  Delete,
  Body,
  Param,
  Query,
  Req,
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

@Controller(['ledger', 'ledgers'])
export class LedgerController {
  constructor(private readonly ledgerService: LedgerService) {}

  @Get('suite')
  @Roles('SUITE_ADMIN')
  async getSuiteLedgers(
    @Req() req: any,
    @Query('search') search?: string,
    @Query('status') status?: string,
  ) {
    return this.ledgerService.getSuiteLedgers(req.user, search, status);
  }

  @Post()
  @Roles('SUITE_ADMIN')
  @HttpCode(HttpStatus.CREATED)
  async createLedger(@Req() req: any, @Body() dto: any) {
    return this.ledgerService.createLedger(req.user, dto);
  }

  @Put(':id')
  @Roles('SUITE_ADMIN')
  async updateLedger(@Req() req: any, @Param('id') id: string, @Body() dto: any) {
    return this.ledgerService.updateLedger(req.user, id, dto);
  }

  @Delete(':id')
  @Roles('SUITE_ADMIN')
  async deleteLedger(@Req() req: any, @Param('id') id: string) {
    return this.ledgerService.deleteLedger(req.user, id);
  }

  @Get('my')
  async getMyLedgers(@Req() req: any) {
    return this.ledgerService.getMyLedgers(req.user);
  }

  @Get('manager')
  async getManagerLedgers(@Req() req: any) {
    return this.ledgerService.getManagerLedgers(req.user);
  }

  @Get(':id/details')
  async getLedgerDetails(@Param('id') id: string, @Req() req: any) {
    return this.ledgerService.getLedgerDetails(req.user, id);
  }

  @Post(':id/employees')
  @Roles('MANAGER', 'SUITE_ADMIN')
  @HttpCode(HttpStatus.CREATED)
  async assignEmployeeToLedger(
    @Req() req: any,
    @Param('id') ledgerId: string,
    @Body('employeeUserId') employeeUserId: string,
  ) {
    return this.ledgerService.assignEmployeeToLedger(req.user, ledgerId, employeeUserId);
  }

  @Post(':id/segments')
  @Roles('MANAGER', 'SUITE_ADMIN')
  @HttpCode(HttpStatus.CREATED)
  async createSegmentInLedger(
    @Req() req: any,
    @Param('id') ledgerId: string,
    @Body() dto: any,
  ) {
    return this.ledgerService.createSegmentInLedger(req.user, ledgerId, dto);
  }

  @Post('movements')
  @HttpCode(HttpStatus.CREATED)
  async recordMovement(@Body() dto: RecordMovementDto) {
    try {
      return await this.ledgerService.recordMoneyMovement(dto);
    } catch (error: any) {
      throw new HttpException(
        error?.message || 'Database error processing movement',
        error?.status || HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }

  @Post('movements/:id/edit')
  @HttpCode(HttpStatus.CREATED)
  async editMovement(
    @Param('id') id: string,
    @Body() dto: EditMovementDto,
  ) {
    return this.ledgerService.editMoneyMovement(id, dto);
  }

  @Get('custodians/:id/balance')
  async getCustodianBalance(
    @Param('id') id: string,
    @Query('companyId') companyId: string,
  ) {
    return this.ledgerService.getCustodianBalance(id, companyId);
  }

  @Post('allocations/inter-company')
  @HttpCode(HttpStatus.CREATED)
  @Roles('accounts', 'approver', 'admin')
  async allocateInterCompanyCost(
    @Body() dto: InterCompanyAllocationDto,
  ) {
    return this.ledgerService.allocateInterCompanyCost(dto);
  }

  @Post('allocations/:id/settle')
  @HttpCode(HttpStatus.OK)
  @Roles('accounts', 'approver', 'admin')
  async settleInterCompanyAllocation(@Param('id') id: string) {
    return this.ledgerService.settleInterCompanyAllocation(id);
  }

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
