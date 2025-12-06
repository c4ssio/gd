"""
Renderer for Geometry Dash
Handles drawing of level objects, player, and UI
"""

import pygame
from typing import Dict, List, Any


class Renderer:
    """Handles all rendering for the game"""
    
    def __init__(self, screen: pygame.Surface, theme_colors: Dict[str, str]):
        """
        Initialize renderer
        
        Args:
            screen: Pygame surface to draw on
            theme_colors: Dictionary with theme color values
        """
        self.screen = screen
        self.theme = theme_colors
        self.camera_x = 0
        
    def hex_to_rgb(self, hex_color: str) -> tuple:
        """Convert hex color string to RGB tuple"""
        hex_color = hex_color.lstrip('#')
        return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))
    
    def set_camera(self, x: float):
        """Set camera position (for scrolling)"""
        self.camera_x = x
    
    def draw_background(self):
        """Draw background"""
        bg_color = self.hex_to_rgb(self.theme.get('background_color', '#1a1a2e'))
        self.screen.fill(bg_color)
    
    def draw_platform(self, platform: Dict[str, Any]):
        """Draw a platform"""
        x = platform.get('x', 0) - self.camera_x
        y = platform.get('y', 0)
        width = platform.get('width', 100)
        height = platform.get('height', 30)
        color = self.hex_to_rgb(platform.get('color', self.theme.get('ground_color', '#16213e')))
        
        pygame.draw.rect(self.screen, color, (x, y, width, height))
        # Add outline for better visibility
        pygame.draw.rect(self.screen, (255, 255, 255), (x, y, width, height), 2)
    
    def draw_obstacle(self, obstacle: Dict[str, Any]):
        """Draw an obstacle (spike, wall, etc.)"""
        x = obstacle.get('x', 0) - self.camera_x
        y = obstacle.get('y', 0)
        width = obstacle.get('width', 50)
        height = obstacle.get('height', 50)
        obstacle_type = obstacle.get('type', 'spike')
        color = self.hex_to_rgb(obstacle.get('color', self.theme.get('accent_color', '#e94560')))
        
        if obstacle_type == 'spike':
            # Draw triangle spike
            rotation = obstacle.get('rotation', 0)
            if rotation == 0:  # Pointing up
                points = [
                    (x + width // 2, y),
                    (x, y + height),
                    (x + width, y + height)
                ]
            elif rotation == 180:  # Pointing down
                points = [
                    (x + width // 2, y + height),
                    (x, y),
                    (x + width, y)
                ]
            else:
                # Default to rectangle if rotation not supported
                pygame.draw.rect(self.screen, color, (x, y, width, height))
                return
            
            pygame.draw.polygon(self.screen, color, points)
            pygame.draw.polygon(self.screen, (255, 255, 255), points, 2)
        else:  # wall or other
            pygame.draw.rect(self.screen, color, (x, y, width, height))
            pygame.draw.rect(self.screen, (255, 255, 255), (x, y, width, height), 2)
    
    def draw_collectible(self, collectible: Dict[str, Any], collectible_type: str = 'star'):
        """Draw a collectible (star or coin)"""
        x = collectible.get('x', 0) - self.camera_x
        y = collectible.get('y', 0)
        size = collectible.get('size', 20)
        color = self.hex_to_rgb(collectible.get('color', '#ffd700'))
        
        if collectible_type == 'star':
            # Draw star shape (simplified as a circle with points)
            pygame.draw.circle(self.screen, color, (int(x + size // 2), int(y + size // 2)), size // 2)
            pygame.draw.circle(self.screen, (255, 255, 255), (int(x + size // 2), int(y + size // 2)), size // 2, 2)
        else:  # coin
            pygame.draw.circle(self.screen, color, (int(x + size // 2), int(y + size // 2)), size // 2)
            pygame.draw.circle(self.screen, (255, 255, 255), (int(x + size // 2), int(y + size // 2)), size // 2, 2)
    
    def draw_player(self, player):
        """Draw the player"""
        x = player.x - self.camera_x
        y = player.y
        width = player.width
        height = player.height
        
        # Draw player as a square (cube mode)
        player_color = (100, 200, 255)  # Bright blue
        pygame.draw.rect(self.screen, player_color, (x, y, width, height))
        pygame.draw.rect(self.screen, (255, 255, 255), (x, y, width, height), 2)
        
        # Add a simple face/icon
        eye_size = 4
        eye_offset = 8
        pygame.draw.circle(self.screen, (255, 255, 255), 
                         (int(x + eye_offset), int(y + eye_offset)), eye_size)
        pygame.draw.circle(self.screen, (255, 255, 255), 
                         (int(x + width - eye_offset), int(y + eye_offset)), eye_size)
    
    def draw_ui(self, progress: float, attempts: int, level_name: str):
        """Draw UI elements"""
        font = pygame.font.Font(None, 36)
        
        # Level name
        name_text = font.render(level_name, True, (255, 255, 255))
        self.screen.blit(name_text, (10, 10))
        
        # Attempts counter
        attempts_text = font.render(f"Attempts: {attempts}", True, (255, 255, 255))
        self.screen.blit(attempts_text, (10, 50))
        
        # Progress bar
        bar_width = 200
        bar_height = 20
        bar_x = self.screen.get_width() - bar_width - 10
        bar_y = 10
        
        # Background
        pygame.draw.rect(self.screen, (50, 50, 50), (bar_x, bar_y, bar_width, bar_height))
        # Progress fill
        fill_width = int(bar_width * progress)
        pygame.draw.rect(self.screen, (0, 255, 0), (bar_x, bar_y, fill_width, bar_height))
        # Border
        pygame.draw.rect(self.screen, (255, 255, 255), (bar_x, bar_y, bar_width, bar_height), 2)
        
        # Progress percentage
        progress_text = font.render(f"{int(progress * 100)}%", True, (255, 255, 255))
        self.screen.blit(progress_text, (bar_x + bar_width // 2 - 30, bar_y + 25))
    
    def draw_game_over(self):
        """Draw game over screen"""
        font_large = pygame.font.Font(None, 72)
        font_small = pygame.font.Font(None, 36)
        
        # Semi-transparent overlay
        overlay = pygame.Surface(self.screen.get_size())
        overlay.set_alpha(200)
        overlay.fill((0, 0, 0))
        self.screen.blit(overlay, (0, 0))
        
        # Game over text
        game_over_text = font_large.render("GAME OVER", True, (255, 0, 0))
        text_rect = game_over_text.get_rect(center=(self.screen.get_width() // 2, 
                                                     self.screen.get_height() // 2 - 50))
        self.screen.blit(game_over_text, text_rect)
        
        # Restart instruction
        restart_text = font_small.render("Press SPACE to restart", True, (255, 255, 255))
        restart_rect = restart_text.get_rect(center=(self.screen.get_width() // 2, 
                                                      self.screen.get_height() // 2 + 20))
        self.screen.blit(restart_text, restart_rect)
    
    def draw_finish_line(self, finish_line_x: float, end_zone_x: float, end_zone_width: float):
        """Draw finish line and end zone"""
        # Draw end zone background (subtle indicator)
        zone_x = end_zone_x - self.camera_x
        if zone_x < self.screen.get_width() + 100:  # Only draw if visible
            zone_rect = pygame.Rect(zone_x, 0, end_zone_width, self.screen.get_height())
            # Semi-transparent green overlay
            overlay = pygame.Surface((end_zone_width, self.screen.get_height()))
            overlay.set_alpha(30)
            overlay.fill((0, 255, 0))
            self.screen.blit(overlay, (zone_x, 0))
        
        # Draw finish line
        line_x = finish_line_x - self.camera_x
        if -10 < line_x < self.screen.get_width() + 10:  # Only draw if visible
            # Thick finish line
            pygame.draw.line(self.screen, (255, 255, 0), 
                           (line_x, 0), (line_x, self.screen.get_height()), 5)
            # Checkered pattern effect
            check_size = 20
            for y in range(0, self.screen.get_height(), check_size * 2):
                pygame.draw.rect(self.screen, (255, 255, 0), 
                               (line_x - 2, y, 4, check_size))
    
    def draw_level_complete(self):
        """Draw level complete screen"""
        font_large = pygame.font.Font(None, 72)
        font_small = pygame.font.Font(None, 36)
        
        # Semi-transparent overlay
        overlay = pygame.Surface(self.screen.get_size())
        overlay.set_alpha(200)
        overlay.fill((0, 0, 0))
        self.screen.blit(overlay, (0, 0))
        
        # Level complete text
        complete_text = font_large.render("LEVEL COMPLETE!", True, (0, 255, 0))
        text_rect = complete_text.get_rect(center=(self.screen.get_width() // 2, 
                                                    self.screen.get_height() // 2 - 50))
        self.screen.blit(complete_text, text_rect)
        
        # Continue instruction
        continue_text = font_small.render("Press SPACE to restart or ESC to quit", True, (255, 255, 255))
        continue_rect = continue_text.get_rect(center=(self.screen.get_width() // 2, 
                                                        self.screen.get_height() // 2 + 20))
        self.screen.blit(continue_text, continue_rect)

