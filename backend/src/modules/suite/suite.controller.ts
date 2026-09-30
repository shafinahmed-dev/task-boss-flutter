import {
  Controller,
  Get,
  Post,
  Body,
  Req,
  HttpCode,
  HttpStatus,
  BadRequestException,
} from '@nestjs/common';
import { SuiteService } from './suite.service.js';
import type { CreateConcernDto, ProvisionManagerDto } from './suite.service.js';
import { Roles } from '../auth/roles.decorator.js';

// All endpoints in this controller require SUITE_ADMIN (level 4) — the global
// JwtAuthGuard + RolesGuard combo enforces this automatically.

@Controller()
@Roles('SUITE_ADMIN')
export class SuiteController {
  constructor(private readonly suiteService: SuiteService) {}

  /**
   * GET /companies
   * Returns all concerns/legal entities belonging to the caller's tenant.
   */
  @Get('companies')
  @HttpCode(HttpStatus.OK)
  async getConcerns(@Req() req: any) {
    const tenantId = req.user?.tenantId;
    if (!tenantId) throw new BadRequestException('No tenant associated with this account');
    return this.suiteService.getConcerns(tenantId);
  }

  /**
   * POST /companies
   * Creates a new concern linked to the active tenant.
   * Auto-provisions a root CustodianAccount for it.
   */
  @Post('companies')
  @HttpCode(HttpStatus.CREATED)
  async createConcern(@Req() req: any, @Body() dto: CreateConcernDto) {
    const tenantId = req.user?.tenantId;
    if (!tenantId) throw new BadRequestException('No tenant associated with this account');
    return this.suiteService.createConcern(tenantId, dto);
  }

  /**
   * GET /suite/managers
   * Returns all MANAGER users in this tenant.
   */
  @Get('suite/managers')
  @HttpCode(HttpStatus.OK)
  async getManagers(@Req() req: any) {
    const tenantId = req.user?.tenantId;
    if (!tenantId) throw new BadRequestException('No tenant associated with this account');
    return this.suiteService.getManagers(tenantId);
  }

  /**
   * POST /suite/provision-manager
   * Provisions a new MANAGER account in the tenant.
   */
  @Post('suite/provision-manager')
  @HttpCode(HttpStatus.CREATED)
  async provisionManager(@Req() req: any, @Body() dto: ProvisionManagerDto) {
    const tenantId = req.user?.tenantId;
    if (!tenantId) throw new BadRequestException('No tenant associated with this account');
    return this.suiteService.provisionManager(tenantId, dto);
  }

  /**
   * GET /suite/ledger-summary
   * Returns aggregated group-level financial metrics.
   */
  @Get('suite/ledger-summary')
  @HttpCode(HttpStatus.OK)
  async getLedgerSummary(@Req() req: any) {
    const tenantId = req.user?.tenantId;
    if (!tenantId) throw new BadRequestException('No tenant associated with this account');
    return this.suiteService.getLedgerSummary(tenantId);
  }
}
