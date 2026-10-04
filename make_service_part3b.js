const fs = require('fs');
const content = `
  async provisionEmployee(tenantId: string, managerCompanyIds: string[], dto: ProvisionEmployeeDto) {
    if (!dto.name?.trim()) throw new BadRequestException('Employee name is required');
    if (!dto.handlePrefix?.trim()) throw new BadRequestException('Handle prefix is required');
    if (!dto.password?.trim()) throw new BadRequestException('Password is required');
    if (!dto.companyId?.trim()) throw new BadRequestException('Company ID is required');

    if (!managerCompanyIds.includes(dto.companyId)) {
      throw new BadRequestException('You are not authorized to provision employees in this concern');
    }

    const tenant = await this.prisma.tenant.findUnique({ where: { id: tenantId } });
    if (!tenant) throw new NotFoundException('Tenant not found');
    const tenantSlug = tenant.slug || 'taskgroup';
    const baseHandle = dto.handlePrefix.trim().toLowerCase().replace(/[^a-z0-9]/g, '');
    const handle = baseHandle + '.' + tenantSlug;

    const existing = await this.prisma.user.findUnique({ where: { handle } });
    if (existing) throw new ConflictException('Handle ' + handle + ' is already taken');

    const passwordHash = await bcrypt.hash(dto.password, 10);

    return this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          handle,
          name: dto.name.trim(),
          role: 'EMPLOYEE',
          tenantId,
          passwordHash,
          rawPassword: dto.password,
          designation: dto.designation?.trim() || 'Staff',
          department: dto.department?.trim() || 'General',
          languagePref: 'en',
        },
      });

      await tx.userCompany.create({
        data: {
          userId: user.id,
          companyId: dto.companyId,
        },
      });

      const custodian = await tx.custodianAccount.create({
        data: {
          name: user.name + ' — Cash',
          type: 'person',
          companyId: dto.companyId,
          linkedUserId: user.id,
        },
      });

      await tx.wallet.create({
        data: {
          name: 'Primary Cash Wallet',
          custodianId: custodian.id,
          companyId: dto.companyId,
        },
      });

      return {
        id: user.id,
        name: user.name,
        handle: user.handle,
        role: user.role,
        designation: user.designation,
        department: user.department,
        rawPassword: user.rawPassword,
        createdAt: user.createdAt,
      };
    });
  }

  async updateEmployee(id: string, managerCompanyIds: string[], dto: any) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      include: { companies: true },
    });
    if (!user) throw new NotFoundException('Employee not found');

    const userCompanyIds = user.companies.map(c => c.companyId);
    const hasAccess = userCompanyIds.some(cId => managerCompanyIds.includes(cId));
    if (!hasAccess) {
      throw new ForbiddenException('Not authorized to update this employee');
    }

    const updateData: Record<string, any> = {};
    if (dto.designation !== undefined) updateData['designation'] = dto.designation;
    if (dto.department !== undefined) updateData['department'] = dto.department;
    if (dto.password !== undefined && dto.password.trim() !== '') {
      updateData['rawPassword'] = dto.password;
      updateData['passwordHash'] = await bcrypt.hash(dto.password, 10);
    }

    const updated = await this.prisma.user.update({
      where: { id },
      data: updateData,
    });

    return {
      id: updated.id,
      name: updated.name,
      handle: updated.handle,
      designation: updated.designation,
      department: updated.department,
      rawPassword: updated.rawPassword,
    };
  }
}
`;
fs.appendFileSync('backend/src/modules/manager/manager.service.ts', content, 'utf8');
console.log('Part 3b done');
