import { Controller, Get, Post, Body, Req, Query, Param, Patch, BadRequestException, ForbiddenException } from '@nestjs/common';
import { ManagerService } from './manager.service.js';
import { Roles } from '../auth/roles.decorator.js';

@Controller('manager')
@Roles('MANAGER', 'SUITE_ADMIN')
export class ManagerController {
  constructor(private readonly managerService: ManagerService) {}

  @Get('overview')
  async getOverview(@Req() req: any, @Query('companyId') companyId?: string, @Query('period') period: 'today'|'week'|'month'|'all' = 'month') {
    if (req.user?.role === 'EMPLOYEE') throw new ForbiddenException();
    const tenantId = req.user?.tenantId;
    const authorizedCompanyIds = req.user?.companyIds;
    if (!tenantId || !authorizedCompanyIds) throw new BadRequestException('Invalid user context');
    return this.managerService.getOverview(tenantId, authorizedCompanyIds, companyId, period);
  }

  @Get('transactions')
  async getTransactions(@Req() req: any) {
    if (req.user?.role === 'EMPLOYEE') throw new ForbiddenException();
    const tenantId = req.user?.tenantId;
    const companyIds = req.user?.companyIds;
    if (!tenantId || !companyIds) throw new BadRequestException('Invalid user context');
    return this.managerService.getManagerTransactions(tenantId, companyIds);
  }

  @Get('employees')
  async getEmployees(@Req() req: any, @Query('companyId') companyId?: string) {
    if (req.user?.role === 'EMPLOYEE') throw new ForbiddenException();
    const authorizedCompanyIds = req.user?.companyIds;
    if (!authorizedCompanyIds) throw new BadRequestException('Invalid user context');
    
    const targetCompanyId = companyId || authorizedCompanyIds[0];
    if (!targetCompanyId) throw new BadRequestException('No authorized concern found');
    if (!authorizedCompanyIds.includes(targetCompanyId)) throw new ForbiddenException('Not authorized for this concern');
    
    return this.managerService.getEmployees(targetCompanyId);
  }

  @Post('employees')
  async provisionEmployee(@Req() req: any, @Body() dto: any) {
    if (req.user?.role === 'EMPLOYEE') throw new ForbiddenException();
    const tenantId = req.user?.tenantId;
    const authorizedCompanyIds = req.user?.companyIds;
    if (!tenantId || !authorizedCompanyIds) throw new BadRequestException('Invalid user context');
    
    return this.managerService.provisionEmployee(tenantId, authorizedCompanyIds, dto);
  }

  @Patch('employees/:id')
  async updateEmployee(@Req() req: any, @Param('id') id: string, @Body() dto: any) {
    if (req.user?.role === 'EMPLOYEE') throw new ForbiddenException();
    const authorizedCompanyIds = req.user?.companyIds;
    if (!authorizedCompanyIds) throw new BadRequestException('Invalid user context');
    
    return this.managerService.updateEmployee(id, authorizedCompanyIds, dto);
  }
}

