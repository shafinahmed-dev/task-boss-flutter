import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  Req,
  HttpCode,
  HttpStatus,
  BadRequestException,
} from '@nestjs/common';
import { SuiteService } from './suite.service.js';
import type { CreateConcernDto, ProvisionManagerDto, UpdateConcernDto, UpdateManagerDto } from './suite.service.js';
import { Roles } from '../auth/roles.decorator.js';

@Controller()
@Roles('SUITE_ADMIN')
export class SuiteController {
  constructor(private readonly suiteService: SuiteService) {}

  @Get('companies')
  @HttpCode(HttpStatus.OK)
  async getConcerns(@Req() req: any) {
    const tenantId = req.user?.tenantId;
    if (!tenantId) throw new BadRequestException('No tenant associated');
    return this.suiteService.getConcerns(tenantId);
  }

  @Post('companies')
  @HttpCode(HttpStatus.CREATED)
  async createConcern(@Req() req: any, @Body() dto: CreateConcernDto) {
    const tenantId = req.user?.tenantId;
    if (!tenantId) throw new BadRequestException('No tenant associated');
    return this.suiteService.createConcern(tenantId, dto);
  }

  @Patch('companies/:id')
  @HttpCode(HttpStatus.OK)
  async updateConcern(@Req() req: any, @Param('id') id: string, @Body() dto: UpdateConcernDto) {
    const tenantId = req.user?.tenantId;
    if (!tenantId) throw new BadRequestException('No tenant associated');
    return this.suiteService.updateConcern(tenantId, id, dto);
  }

  @Delete('companies/:id')
  @HttpCode(HttpStatus.OK)
  async deleteConcern(@Req() req: any, @Param('id') id: string) {
    const tenantId = req.user?.tenantId;
    if (!tenantId) throw new BadRequestException('No tenant associated');
    return this.suiteService.deleteConcern(tenantId, id);
  }

  @Get('suite/managers')
  @HttpCode(HttpStatus.OK)
  async getManagers(@Req() req: any) {
    const tenantId = req.user?.tenantId;
    if (!tenantId) throw new BadRequestException('No tenant associated');
    return this.suiteService.getManagers(tenantId);
  }

  @Post('suite/provision-manager')
  @HttpCode(HttpStatus.CREATED)
  async provisionManager(@Req() req: any, @Body() dto: ProvisionManagerDto) {
    const tenantId = req.user?.tenantId;
    if (!tenantId) throw new BadRequestException('No tenant associated');
    return this.suiteService.provisionManager(tenantId, dto);
  }

  @Patch('suite/managers/:id')
  @HttpCode(HttpStatus.OK)
  async updateManager(@Req() req: any, @Param('id') id: string, @Body() dto: UpdateManagerDto) {
    const tenantId = req.user?.tenantId;
    if (!tenantId) throw new BadRequestException('No tenant associated');
    return this.suiteService.updateManager(tenantId, id, dto);
  }

  @Delete('suite/managers/:id')
  @HttpCode(HttpStatus.OK)
  async deleteManager(@Req() req: any, @Param('id') id: string) {
    const tenantId = req.user?.tenantId;
    if (!tenantId) throw new BadRequestException('No tenant associated');
    return this.suiteService.deleteManager(tenantId, id);
  }

  @Get('suite/ledger-summary')
  @HttpCode(HttpStatus.OK)
  async getLedgerSummary(@Req() req: any) {
    const tenantId = req.user?.tenantId;
    if (!tenantId) throw new BadRequestException('No tenant associated');
    return this.suiteService.getLedgerSummary(tenantId);
  }
}
