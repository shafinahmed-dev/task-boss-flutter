import {
  Injectable,
  UnauthorizedException,
  ConflictException,
  BadRequestException
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../../database/prisma.service.js';

// ── DTOs ──────────────────────────────────────────────────────────────────

export interface LoginDto {
  handle: string;     // e.g. "suite.taskgroup", "ceoman.taskgroup"
  password: string;
  // Legacy compat: accept email field as alias for handle
  email?: string;
  companyId?: string;
}

export interface RegisterCompanyDto {
  companyName: string;
  slug: string;
  password: string;
  suiteName?: string;
}

export interface RegisterDto {
  name: string;
  designation?: string;
  department?: string;
  email: string;
  phone: string;
  password: string;
  companyId?: string;
}

export interface UpdateProfileDto {
  name?: string;
  designation?: string;
  department?: string;
}

export interface AuthResult {
  access_token: string;
  token_type: 'Bearer';
  expires_in: number;
  user: {
    id: string;
    handle: string;
    name: string;
    email?: string;
    phone?: string;
    designation?: string;
    department?: string;
    role: string;
    tenantId?: string;
    companyIds: string[];
    custodianId?: string;
  };
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
  ) {}

  /**
   * POST /auth/login
   *
   * Authenticates a user by handle (or legacy email/name) + password.
   * Returns a signed JWT containing:
   *   • sub: user ID
   *   • handle: user handle
   *   • role: user role
   *   • tenantId: tenant UUID
   *   • companyIds: array of authorized company IDs
   */
  async login(dto: LoginDto): Promise<AuthResult> {
    // Normalize: support both "handle" and legacy "email" field
    const identifier = (dto.handle || dto.email || '').trim().toLowerCase();

    if (!identifier) {
      throw new BadRequestException('Handle is required');
    }

    // Try to find user by handle first, then fall back to email/name
    const user = await this.prisma.user.findFirst({
      where: {
        OR: [
          { handle: identifier },
          { email: identifier },
          { name: identifier },
        ]
      },
      select: {
        id: true,
        handle: true,
        name: true,
        email: true,
        phone: true,
        designation: true,
        department: true,
        role: true,
        tenantId: true,
        languagePref: true,
        passwordHash: true,
        createdAt: true,
        companies: {
          select: { companyId: true },
        },
        custodianAccounts: {
          select: { id: true },
          take: 1,
        },
      },
    });

    if (!user) {
      throw new UnauthorizedException('Invalid credentials');
    }

    // Verify password
    const passwordValid = await bcrypt.compare(
      dto.password,
      user.passwordHash,
    );
    if (!passwordValid) {
      throw new UnauthorizedException('Invalid credentials');
    }

    // Build authorized company IDs
    const allCompanyIds = user.companies.map(
      (uc: { companyId: string }) => uc.companyId,
    );

    // If a specific company was requested, validate it
    let authorizedCompanyIds: string[];
    if (dto.companyId) {
      if (!allCompanyIds.includes(dto.companyId)) {
        throw new UnauthorizedException(
          `User is not authorized for company ${dto.companyId}`,
        );
      }
      authorizedCompanyIds = [dto.companyId];
    } else {
      authorizedCompanyIds = allCompanyIds;
    }

    // Sign JWT with handle & tenantId
    const payload = {
      sub: user.id,
      handle: user.handle,
      role: user.role,
      tenantId: user.tenantId ?? undefined,
      companyIds: authorizedCompanyIds,
    };

    const expiresIn = '8h';
    const access_token = this.jwtService.sign(payload, { expiresIn });

    // Decode to get exp
    const decoded = this.jwtService.decode(access_token) as { exp: number };
    const expires_in = decoded.exp - Math.floor(Date.now() / 1000);

    return {
      access_token,
      token_type: 'Bearer',
      expires_in,
      user: {
        id: user.id,
        handle: user.handle,
        name: user.name,
        email: user.email ?? undefined,
        phone: user.phone ?? undefined,
        designation: user.designation ?? 'User',
        department: user.department ?? 'General',
        role: user.role,
        tenantId: user.tenantId ?? undefined,
        companyIds: authorizedCompanyIds,
        custodianId: user.custodianAccounts[0]?.id,
      },
    };
  }

  // ── POST /auth/register-company ──────────────────────────────────────

  async registerCompany(dto: RegisterCompanyDto) {
    // Sanitize slug: lowercase, alphanumeric only
    const sanitizedSlug = (dto.slug || '')
      .toLowerCase()
      .replace(/[^a-z0-9]/g, '');

    if (!sanitizedSlug || sanitizedSlug.length < 2) {
      throw new BadRequestException('Slug must be at least 2 alphanumeric characters');
    }

    if (!dto.companyName || dto.companyName.trim().length < 2) {
      throw new BadRequestException('Company name is required (min 2 characters)');
    }

    if (!dto.password || dto.password.length < 6) {
      throw new BadRequestException('Password must be at least 6 characters');
    }

    // Check slug uniqueness
    const existingTenant = await this.prisma.tenant.findUnique({
      where: { slug: sanitizedSlug },
    });
    if (existingTenant) {
      throw new ConflictException('Company handle slug is already taken');
    }

    const passwordHash = await bcrypt.hash(dto.password, 10);
    const suiteHandle = `suite.${sanitizedSlug}`;

    return this.prisma.$transaction(async (tx) => {
      // 1. Create Tenant
      const tenant = await tx.tenant.create({
        data: {
          name: dto.companyName.trim(),
          slug: sanitizedSlug,
        },
      });

      // 2. Create root Suite user
      const suiteUser = await tx.user.create({
        data: {
          handle: suiteHandle,
          name: dto.suiteName?.trim() || `${dto.companyName.trim()} Suite`,
          role: 'SUITE_ADMIN',
          tenantId: tenant.id,
          languagePref: 'en',
          passwordHash,
          rawPassword: dto.password,
        },
      });

      // 7. Generate JWT
      const payload = {
        sub: suiteUser.id,
        handle: suiteUser.handle,
        role: suiteUser.role,
        tenantId: tenant.id,
        companyIds: [],
      };
      const access_token = this.jwtService.sign(payload, { expiresIn: '8h' });

      return {
        success: true,
        handle: suiteHandle,
        token: access_token,
        user: {
          id: suiteUser.id,
          handle: suiteUser.handle,
          name: suiteUser.name,
          role: suiteUser.role,
          tenantId: tenant.id,
        },
      };
    });
  }

  /**
   * POST /auth/register
   * Registers a new user and creates their custodian account.
   */
  async register(dto: RegisterDto) {
    if (!dto.password || !dto.name) {
      throw new BadRequestException('Missing required fields');
    }

    if (dto.password.length < 6) {
      throw new BadRequestException('Password must be at least 6 characters');
    }

    let companyId = dto.companyId;
    if (!companyId) {
      const company = await this.prisma.company.findFirst();
      if (!company) {
        throw new BadRequestException('No default company found. Please provide companyId.');
      }
      companyId = company.id;
    }

    // Lookup the company's tenant
    const company = await this.prisma.company.findUnique({
      where: { id: companyId },
      include: { tenant: true },
    });
    const tenantSlug = company?.tenant?.slug || 'taskgroup';
    
    // Generate a handle
    const baseHandle = (dto.email || dto.name || 'user')
      .toLowerCase()
      .replace(/[^a-z0-9]/g, '')
      .replace(/@.*$/, '');

    let handle = `${baseHandle}.${tenantSlug}`;
    const existing = await this.prisma.user.findUnique({ where: { handle } });
    if (existing) {
      handle = `${baseHandle}${Date.now() % 10000}.${tenantSlug}`;
    }

    if (dto.email) {
      const existingUser = await this.prisma.user.findUnique({
        where: { email: dto.email }
      });
      if (existingUser) {
        throw new ConflictException('Email already exists');
      }
    }

    const passwordHash = await bcrypt.hash(dto.password, 10);

    return this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          handle,
          name: dto.name,
          email: dto.email || null,
          phone: dto.phone || null,
          designation: dto.designation || 'User',
          department: dto.department || 'General',
          role: 'EMPLOYEE',
          tenantId: company?.tenantId ?? null,
          languagePref: 'en',
          passwordHash,
        }
      });

      await tx.userCompany.create({
        data: {
          userId: user.id,
          companyId: companyId as string,
        }
      });

      const custodian = await tx.custodianAccount.create({
        data: {
          type: 'person',
          name: user.name,
          companyId: companyId as string,
          linkedUserId: user.id,
        }
      });

      await tx.wallet.create({
        data: {
          custodianId: custodian.id,
          companyId: companyId as string,
          name: 'Cash in Hand',
          type: 'CASH',
          isDefault: true,
        },
      });

      return {
        id: user.id,
        handle: user.handle,
        name: user.name,
        email: user.email,
        phone: user.phone,
        designation: user.designation ?? 'User',
        department: user.department ?? 'General',
        role: user.role,
        tenantId: user.tenantId,
        companyId: companyId as string,
        custodianId: custodian.id
      };
    });
  }

  /**
   * PATCH /auth/profile
   * Updates user designation, department, and/or name.
   */
  async updateProfile(userId: string, dto: UpdateProfileDto) {
    const data: { name?: string; designation?: string; department?: string } = {};
    if (dto.name !== undefined) data.name = dto.name;
    if (dto.designation !== undefined) data.designation = dto.designation;
    if (dto.department !== undefined) data.department = dto.department;

    const user = await this.prisma.user.update({
      where: { id: userId },
      data,
      select: {
        id: true,
        name: true,
        email: true,
        phone: true,
        designation: true,
        department: true,
        role: true,
        companies: {
          select: { companyId: true },
        },
        custodianAccounts: {
          select: { id: true },
          take: 1,
        },
      },
    });

    return {
      id: user.id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      designation: user.designation ?? 'User',
      department: user.department ?? 'General',
      role: user.role,
      companyIds: user.companies.map((c: { companyId: string }) => c.companyId),
      custodianId: user.custodianAccounts[0]?.id,
    };
  }

  /**
   * Seed a user (for development/testing).
   * Hashes the password and creates the user record.
   */
  async createUser(data: {
    name: string;
    role: string;
    password: string;
    companyIds: string[];
    handle?: string;
  }) {
    const passwordHash = await bcrypt.hash(data.password, 10);

    let tenantId: string | null = null;
    let tenantSlug = 'taskgroup';
    if (data.companyIds && data.companyIds.length > 0) {
      const comp = await this.prisma.company.findUnique({
        where: { id: data.companyIds[0] },
        include: { tenant: true },
      });
      if (comp) {
        tenantId = comp.tenantId;
        if (comp.tenant?.slug) {
          tenantSlug = comp.tenant.slug;
        }
      }
    }

    const baseHandle = (data.handle || data.name).toLowerCase().replace(/[^a-z0-9]/g, '');
    let handle = `${baseHandle}.${tenantSlug}`;
    const existing = await this.prisma.user.findUnique({ where: { handle } });
    if (existing) {
      handle = `${baseHandle}${Date.now() % 10000}.${tenantSlug}`;
    }

    return this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          handle,
          name: data.name,
          role: data.role,
          tenantId,
          languagePref: 'bn',
          passwordHash,
        },
      });

      // Link to companies
      if (data.companyIds.length > 0) {
        await tx.userCompany.createMany({
          data: data.companyIds.map((companyId) => ({
            userId: user.id,
            companyId,
          })),
        });
      }

      return user;
    });
  }
}