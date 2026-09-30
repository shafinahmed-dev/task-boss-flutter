import { Controller, Post, Body, HttpCode, HttpStatus, BadRequestException } from '@nestjs/common';
import { AuthService } from './auth.service.js';
import type { LoginDto, RegisterDto } from './auth.service.js';
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
}