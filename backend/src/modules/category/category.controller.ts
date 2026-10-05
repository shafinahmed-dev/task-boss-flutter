import { Controller, Get, Post, Body, Req, Query, BadRequestException, ForbiddenException } from '@nestjs/common';
import { CategoryService } from './category.service.js';
import { Roles } from '../auth/roles.decorator.js';

@Controller()
export class CategoryController {
  constructor(private readonly categoryService: CategoryService) {}

  @Get('categories')
  async getCategories(@Req() req: any, @Query('companyId') companyId: string, @Query('flowType') flowType?: string, @Query('type') type?: string) {
    if (!companyId) {
      throw new BadRequestException('companyId query parameter is required');
    }
    const userCompanyIds = req.user?.companyIds || [];
    if (req.user?.role !== 'SUITE_ADMIN' && !userCompanyIds.includes(companyId)) {
      throw new ForbiddenException('Not authorized for this company');
    }
    return this.categoryService.getCategories(companyId, flowType || type);
  }

  @Post('manager/categories')
  @Roles('MANAGER', 'SUITE_ADMIN')
  async createCategory(@Req() req: any, @Body() dto: { name: string; type?: string; companyId: string }) {
    if (req.user?.role === 'EMPLOYEE') {
      throw new ForbiddenException('Employees cannot create categories');
    }
    const tenantId = req.user?.tenantId;
    const companyIds = req.user?.companyIds;
    if (!tenantId || !companyIds) {
      throw new BadRequestException('Invalid user context');
    }
    return this.categoryService.createCategory(tenantId, companyIds, dto);
  }

  @Get('manager/transactions/category-summary')
  @Roles('MANAGER', 'SUITE_ADMIN')
  async getCategorySummary(@Req() req: any, @Query('companyId') companyId: string, @Query('categoryId') categoryId: string) {
    if (req.user?.role === 'EMPLOYEE') {
      throw new ForbiddenException();
    }
    if (!companyId || !categoryId) {
      throw new BadRequestException('companyId and categoryId are required');
    }
    const companyIds = req.user?.companyIds || [];
    if (!companyIds.includes(companyId)) {
      throw new ForbiddenException('Not authorized for this company');
    }
    return this.categoryService.getCategorySummary(companyId, categoryId);
  }
}
