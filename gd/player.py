"""
Player class for Geometry Dash
Handles player physics, movement, and game mode mechanics
"""

import pygame
from typing import Dict, Any


class Player:
    """Player character with physics and game mode support"""
    
    def __init__(self, start_config: Dict[str, Any]):
        """
        Initialize player with starting configuration
        
        Args:
            start_config: Dictionary with start_x, start_y, start_mode, start_speed, etc.
        """
        self.x = start_config.get('start_x', 100)
        self.y = start_config.get('start_y', 300)
        self.mode = start_config.get('start_mode', 'cube')
        self.speed = self._get_speed_value(start_config.get('start_speed', 'normal'))
        self.size = start_config.get('start_size', 'normal')
        self.gravity = start_config.get('start_gravity', 'down')
        
        # Physics constants
        self.gravity_force = 0.8
        self.jump_force = -12
        self.max_fall_speed = 15
        self.velocity_y = 0
        self.velocity_x = self.speed
        
        # Size multipliers
        self.size_multipliers = {
            'normal': 1.0,
            'mini': 0.5,
            'large': 1.5
        }
        
        # Player dimensions
        self.width = 30 * self.size_multipliers.get(self.size, 1.0)
        self.height = 30 * self.size_multipliers.get(self.size, 1.0)
        
        # State
        self.on_ground = False
        self.is_jumping = False
        
    def _get_speed_value(self, speed_name: str) -> float:
        """Convert speed name to pixel value"""
        speeds = {
            'normal': 4.0,
            'slow': 2.0,
            'fast': 6.0,
            'very_fast': 8.0
        }
        return speeds.get(speed_name, 4.0)
    
    def jump(self):
        """Make the player jump (cube mode)"""
        if self.mode == 'cube' and self.on_ground:
            self.velocity_y = self.jump_force
            self.on_ground = False
            self.is_jumping = True
    
    def update(self, platforms: list, obstacles: list):
        """
        Update player physics and position
        
        Args:
            platforms: List of platform objects to check collision with
            obstacles: List of obstacle objects to check collision with
        """
        # Apply gravity
        if self.gravity == 'down':
            self.velocity_y += self.gravity_force
            if self.velocity_y > self.max_fall_speed:
                self.velocity_y = self.max_fall_speed
        else:  # up
            self.velocity_y -= self.gravity_force
            if self.velocity_y < -self.max_fall_speed:
                self.velocity_y = -self.max_fall_speed
        
        # Move horizontally (auto-scroll)
        self.x += self.velocity_x
        
        # Move vertically
        new_y = self.y + self.velocity_y
        
        # Check platform collisions
        self.on_ground = False
        player_rect = pygame.Rect(self.x, new_y, self.width, self.height)
        
        for platform in platforms:
            platform_rect = self._get_platform_rect(platform)
            
            # Check if player is on top of platform
            if (player_rect.bottom >= platform_rect.top and 
                player_rect.bottom <= platform_rect.top + 10 and
                player_rect.right > platform_rect.left and
                player_rect.left < platform_rect.right and
                self.velocity_y >= 0):
                new_y = platform_rect.top - self.height
                self.velocity_y = 0
                self.on_ground = True
                self.is_jumping = False
                break
        
        self.y = new_y
        
        # Prevent falling through bottom of screen (safety check)
        if self.y + self.height > 800:  # Screen height + buffer
            self.y = 800 - self.height
            self.velocity_y = 0
            self.on_ground = True
        
        # Prevent going above ceiling
        if self.y < 0:
            self.y = 0
            self.velocity_y = 0
        
        # Check obstacle collisions
        player_rect = pygame.Rect(self.x, self.y, self.width, self.height)
        for obstacle in obstacles:
            obstacle_rect = self._get_obstacle_rect(obstacle)
            if player_rect.colliderect(obstacle_rect):
                return True  # Collision detected
        
        return False  # No collision
    
    def _get_platform_rect(self, platform: Dict[str, Any]) -> pygame.Rect:
        """Get pygame Rect for a platform object"""
        return pygame.Rect(
            platform.get('x', 0),
            platform.get('y', 0),
            platform.get('width', 100),
            platform.get('height', 30)
        )
    
    def _get_obstacle_rect(self, obstacle: Dict[str, Any]) -> pygame.Rect:
        """Get pygame Rect for an obstacle object"""
        return pygame.Rect(
            obstacle.get('x', 0),
            obstacle.get('y', 0),
            obstacle.get('width', 50),
            obstacle.get('height', 50)
        )
    
    def get_rect(self) -> pygame.Rect:
        """Get player's collision rectangle"""
        return pygame.Rect(self.x, self.y, self.width, self.height)
    
    def reset(self, start_config: Dict[str, Any]):
        """Reset player to starting position"""
        self.x = start_config.get('start_x', 100)
        self.y = start_config.get('start_y', 300)
        self.velocity_y = 0
        self.on_ground = False
        self.is_jumping = False
        self.mode = start_config.get('start_mode', 'cube')
        self.speed = self._get_speed_value(start_config.get('start_speed', 'normal'))
        self.velocity_x = self.speed

