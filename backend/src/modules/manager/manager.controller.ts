import { Controller, Get, Post, Body, Req, HttpStatus, HttpCode, BadRequestException } from '@nestjs/common';
import { ManagerService } from './manager.service.js';
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
}
