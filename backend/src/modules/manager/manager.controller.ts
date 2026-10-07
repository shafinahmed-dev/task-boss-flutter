import { Controller, Get, Post, Body, Req, Query, Param, Patch, BadRequestException, ForbiddenException } from '@nestjs/common';
import { ManagerService } from './manager.service.js';
import { Roles } from '../auth/roles.decorator.js';

@Controller('manager')
@Roles('MANAGER', 'SUITE_ADMIN')
export class ManagerController {
  constructor(private readonly managerService: ManagerService) {}

  @Get('overview')
  async getOverview(@Req() req: any, @Query('companyId') companyId?: string, @Query('range') range?: string) {
    if (req.user?.role === 'EMPLOYEE') throw new ForbiddenException();
    const tenantId = req.user?.tenantId;
    const authorizedCompanyIds = req.user?.companyIds;
    const userId = req.user?.id || req.user?.sub || req.user?.userId;
    if (!tenantId || !authorizedCompanyIds || !userId) throw new BadRequestException('Invalid user context');
    const targetCompanyId = (!companyId || companyId === '') ? authorizedCompanyIds[0] : companyId;
    return this.managerService.getOverview(targetCompanyId, range, req.user);
  }

  @Get('transactions')
  async getTransactions(@Req() req: any, @Query('companyId') companyId?: string) {
    if (req.user?.role === 'EMPLOYEE') throw new ForbiddenException();
    return this.managerService.getAllTransactions(companyId, req.user);
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
    const tenantId = req.user?.tenantId;
    const authorizedCompanyIds = req.user?.companyIds;
    if (!tenantId || !authorizedCompanyIds) throw new BadRequestException('Invalid user context');
    
    return this.managerService.updateEmployee(id, tenantId, authorizedCompanyIds, dto);
  }
}

