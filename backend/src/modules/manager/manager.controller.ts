import { Controller, Get, Post, Body, Req, HttpStatus, HttpCode, BadRequestException } from '@nestjs/common';
import { ManagerService } from './manager.service.js';
import type { ProvisionEmployeeDto } from './manager.service.js';
import { Roles } from '../auth/roles.decorator.js';

@Controller('manager')
@Roles('MANAGER')
export class ManagerController {
  constructor(private readonly managerService: ManagerService) {}

  @Get('overview')
  @HttpCode(HttpStatus.OK)
  async getOverview(@Req() req: any) {
    const tenantId = req.user?.tenantId;
    const companyIds = req.user?.companyIds;
    if (!tenantId || !companyIds) throw new BadRequestException('Invalid user context');
    return this.managerService.getOverview(tenantId, companyIds);
  }

  @Get('transactions')
  @HttpCode(HttpStatus.OK)
  async getTransactions(@Req() req: any) {
    const tenantId = req.user?.tenantId;
    const companyIds = req.user?.companyIds;
    if (!tenantId || !companyIds) throw new BadRequestException('Invalid user context');
    return this.managerService.getManagerTransactions(tenantId, companyIds);
  }

  @Post('employees')
  @HttpCode(HttpStatus.CREATED)
  async provisionEmployee(@Req() req: any, @Body() dto: ProvisionEmployeeDto) {
    const tenantId = req.user?.tenantId;
    const companyIds = req.user?.companyIds;
    if (!tenantId || !companyIds) throw new BadRequestException('Invalid user context');
    return this.managerService.provisionEmployee(tenantId, companyIds, dto);
  }
}
