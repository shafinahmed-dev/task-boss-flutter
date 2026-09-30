import { Controller, Post, Patch, Body, HttpCode, HttpStatus, Req, BadRequestException } from '@nestjs/common';
import { AuthService } from './auth.service.js';
import type { LoginDto, RegisterDto, UpdateProfileDto } from './auth.service.js';
import { Public } from './public.decorator.js';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  /**
   * POST /auth/login
   * Authenticates user and returns signed JWT.
   * Marked @Public() so it bypasses JWT authentication.
   */
  @Public()
  @Post('login')
  @HttpCode(HttpStatus.OK)
  async login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }

  /**
   * POST /auth/register
   * Registers a new user and creates their custodian account.
   */
  @Public()
  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  async register(@Body() dto: RegisterDto) {
    return this.authService.register(dto);
  }

  /**
   * PATCH /auth/profile
   * Updates user profile fields (designation, department, name).
   * Protected by JWT Guard.
   */
  @Patch('profile')
  @HttpCode(HttpStatus.OK)
  async updateProfile(@Req() req: any, @Body() dto: UpdateProfileDto) {
    const userId = req.user?.id || req.user?.sub || req.user?.userId;
    if (!userId) {
      throw new BadRequestException('User identification missing from token');
    }
    return this.authService.updateProfile(userId, dto);
  }
}