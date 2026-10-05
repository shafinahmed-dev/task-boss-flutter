import { Controller, Get, Post, Patch, Delete, Body, Param, Req, Query, BadRequestException, ForbiddenException } from '@nestjs/common';
import { CategoryService } from './category.service.js';
import { Roles } from '../auth/roles.decorator.js';

@Controller()
export class CategoryController {
  constructor(private readonly categoryService: CategoryService) {}

  @Get('categories')
  async getCategories(@Req() req: any, @Query('companyId') companyId: string, @Query('flowType') flowType?: string, @Query('type') type?: string) {
    return this.categoryService.getCategories(req.user, companyId, flowType || type);
  }

  @Post('manager/categories')
  @Roles('MANAGER', 'SUITE_ADMIN')
  async createCategory(@Req() req: any, @Body() dto: { name: string; type?: string; companyId: string }) {
    if (req.user?.role === 'EMPLOYEE') {
      throw new ForbiddenException('Employees cannot create categories');
    }
    return this.categoryService.createCategory(req.user, dto);
  }

  @Patch('manager/categories/:id')
  @Roles('MANAGER', 'SUITE_ADMIN')
  async updateCategory(@Req() req: any, @Param('id') id: string, @Body() dto: { name?: string; type?: string }) {
    if (req.user?.role === 'EMPLOYEE') {
      throw new ForbiddenException('Employees cannot update categories');
    }
    return this.categoryService.updateCategory(req.user, id, dto);
  }

  @Delete('manager/categories/:id')
  @Roles('MANAGER', 'SUITE_ADMIN')
  async deleteCategory(@Req() req: any, @Param('id') id: string) {
    if (req.user?.role === 'EMPLOYEE') {
      throw new ForbiddenException('Employees cannot delete categories');
    }
    return this.categoryService.deleteCategory(req.user, id);
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
