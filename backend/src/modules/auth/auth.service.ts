import {
  Injectable,
  UnauthorizedException,
  ConflictException,
  BadRequestException
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../../database/prisma.service.js';

export interface LoginDto {
  email: string;      // We use name or email as identifier
  password: string;
  companyId?: string; // Optional — scope the token to a specific company
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
    name: string;
    email?: string;
    phone?: string;
    designation?: string;
    department?: string;
    role: string;
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
   * Authenticates a user by name (used as email equivalent) + password.
   * Returns a signed JWT containing:
   *   • sub: user ID
   *   • role: user role
   *   • companyIds: array of authorized company IDs
   */
  async login(dto: LoginDto): Promise<AuthResult> {
    // Find user by email or name
    const user = await this.prisma.user.findFirst({
      where: {
        OR: [
          { email: dto.email },
          { name: dto.email }
        ]
      },
      select: {
        id: true,
        name: true,
        email: true,
        phone: true,
        designation: true,
        department: true,
        role: true,
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

    // Sign JWT
    const payload = {
      sub: user.id,
      role: user.role,
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
        name: user.name,
        email: user.email ?? dto.email,
        phone: user.phone ?? undefined,
        designation: user.designation ?? 'User',
        department: user.department ?? 'General',
        role: user.role,
        companyIds: authorizedCompanyIds,
        custodianId: user.custodianAccounts[0]?.id,
      },
    };
  }

  /**
   * POST /auth/register
   * Registers a new user and creates their custodian account.
   */
  async register(dto: RegisterDto) {
    if (!dto.email || !dto.password || !dto.name) {
      throw new BadRequestException('Missing required fields');
    }

    if (dto.password.length < 6) {
      throw new BadRequestException('Password must be at least 6 characters');
    }

    const existingUser = await this.prisma.user.findUnique({
      where: { email: dto.email }
    });

    if (existingUser) {
      throw new ConflictException('Email already exists');
    }

    let companyId = dto.companyId;
    if (!companyId) {
      const company = await this.prisma.company.findFirst();
      if (!company) {
        throw new BadRequestException('No default company found. Please provide companyId.');
      }
      companyId = company.id;
    }

    const passwordHash = await bcrypt.hash(dto.password, 10);

    return this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          name: dto.name,
          email: dto.email,
          phone: dto.phone,
          designation: dto.designation || 'User',
          department: dto.department || 'General',
          role: 'collector',
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

      return {
        id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        designation: user.designation ?? 'User',
        department: user.department ?? 'General',
        role: user.role,
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
  }) {
    const passwordHash = await bcrypt.hash(data.password, 10);

    return this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          name: data.name,
          role: data.role,
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