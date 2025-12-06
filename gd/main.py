"""
Geometry Dash - Main Game Entry Point
Run this file to play the game
"""

import pygame
import sys
from pathlib import Path

from gd.game import LevelLoader, LevelProcessor
from gd.player import Player
from gd.renderer import Renderer
from gd.moving_objects import create_moving_platforms, MovingPlatform


class GeometryDash:
    """Main game class"""
    
    def __init__(self, level_id: str = "level_01"):
        """Initialize the game"""
        pygame.init()
        
        # Screen setup
        self.screen_width = 1200
        self.screen_height = 700
        self.screen = pygame.display.set_mode((self.screen_width, self.screen_height))
        pygame.display.set_caption("Geometry Dash")
        self.clock = pygame.time.Clock()
        
        # Load level
        self.level_loader = LevelLoader()
        level_data = self.level_loader.load_level(level_id)
        self.level_processor = LevelProcessor(level_data)
        
        # Initialize player
        player_start = self.level_processor.get_player_start()
        self.player = Player(player_start)
        
        # Initialize renderer
        theme_colors = self.level_processor.get_theme_colors()
        self.renderer = Renderer(self.screen, theme_colors)
        
        # Game state
        self.running = True
        self.game_over = False
        self.level_complete = False
        self.attempts = 0
        self.level_name = self.level_processor.metadata.get('name', 'Level')
        self.level_length = self.level_processor.get_level_length()
        
        # Get end zone configuration
        self.end_zone = self.level_processor.get_end_zone()
        self.finish_line_x = self.end_zone.get('finish_line_x', self.level_length)
        self.end_zone_x = self.end_zone.get('x', self.level_length - 100)
        self.end_zone_width = self.end_zone.get('width', 100)
        
        # Get level objects
        self.static_platforms = [p for p in self.level_processor.get_all_platforms() 
                                 if 'movement' not in p]
        self.obstacles = self.level_processor.get_all_obstacles()
        self.collectibles = self.level_processor.get_all_collectibles()
        self.collected_items = set()  # Track collected items by ID
        
        # Handle moving platforms separately
        moving_platforms_data = self.level_processor.objects.get('moving_platforms', [])
        self.moving_platforms = create_moving_platforms(moving_platforms_data)
        
        # Get jump pads
        self.jump_pads = self.level_processor.objects.get('jump_pads', [])
        
    def handle_input(self):
        """Handle user input"""
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                self.running = False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_SPACE:
                    if self.game_over:
                        self.restart_level()
                    else:
                        self.player.jump()
                elif event.key == pygame.K_ESCAPE:
                    self.running = False
    
    def update(self):
        """Update game state"""
        if self.game_over:
            return
        
        # Update moving platforms
        for moving_platform in self.moving_platforms:
            moving_platform.update()
        
        # Combine static and moving platforms for collision
        all_platforms = self.static_platforms.copy()
        for mp in self.moving_platforms:
            all_platforms.append(mp.get_data())
        
        # Update player
        collision = self.player.update(all_platforms, self.obstacles)
        
        if collision:
            self.game_over = True
            self.attempts += 1
            return
        
        # Check jump pads
        player_rect = self.player.get_rect()
        for jump_pad in self.jump_pads:
            jump_pad_rect = pygame.Rect(
                jump_pad.get('x', 0),
                jump_pad.get('y', 0),
                jump_pad.get('width', 50),
                jump_pad.get('height', 20)
            )
            if player_rect.colliderect(jump_pad_rect) and self.player.on_ground:
                self.player.velocity_y = -jump_pad.get('force', 15)
                self.player.on_ground = False
        
        # Check collectibles
        for collectible in self.collectibles:
            if collectible.get('id') in self.collected_items:
                continue
            
            collectible_rect = pygame.Rect(
                collectible.get('x', 0),
                collectible.get('y', 0),
                collectible.get('size', 20),
                collectible.get('size', 20)
            )
            
            if player_rect.colliderect(collectible_rect):
                self.collected_items.add(collectible.get('id'))
        
        # Update camera to follow player
        camera_x = self.player.x - self.screen_width // 3
        if camera_x < 0:
            camera_x = 0
        self.renderer.set_camera(camera_x)
        
        # Check if player completed level (reached finish line)
        if self.player.x >= self.finish_line_x and not self.level_complete:
            self.level_complete = True
            self.game_over = True
            print("Level completed!")
    
    def restart_level(self):
        """Restart the current level"""
        player_start = self.level_processor.get_player_start()
        self.player.reset(player_start)
        self.game_over = False
        self.level_complete = False
        self.collected_items.clear()
        self.renderer.set_camera(0)
    
    def draw(self):
        """Draw everything"""
        # Draw background
        self.renderer.draw_background()
        
        # Draw static platforms
        for platform in self.static_platforms:
            self.renderer.draw_platform(platform)
        
        # Draw moving platforms
        for moving_platform in self.moving_platforms:
            self.renderer.draw_platform(moving_platform.get_data())
        
        # Draw jump pads
        for jump_pad in self.jump_pads:
            x = jump_pad.get('x', 0) - self.renderer.camera_x
            y = jump_pad.get('y', 0)
            width = jump_pad.get('width', 50)
            height = jump_pad.get('height', 20)
            color = self.renderer.hex_to_rgb(jump_pad.get('color', '#00ff88'))
            pygame.draw.rect(self.renderer.screen, color, (x, y, width, height))
            pygame.draw.rect(self.renderer.screen, (255, 255, 255), (x, y, width, height), 2)
        
        # Draw obstacles
        for obstacle in self.obstacles:
            self.renderer.draw_obstacle(obstacle)
        
        # Draw collectibles (only uncollected ones)
        for collectible in self.collectibles:
            if collectible.get('id') not in self.collected_items:
                # Determine type (star or coin)
                collectible_type = 'star'
                if 'coin' in collectible.get('id', '').lower():
                    collectible_type = 'coin'
                self.renderer.draw_collectible(collectible, collectible_type)
        
        # Draw player
        self.renderer.draw_player(self.player)
        
        # Draw finish line and end zone
        self.renderer.draw_finish_line(self.finish_line_x, self.end_zone_x, self.end_zone_width)
        
        # Calculate progress
        progress = min(self.player.x / self.level_length, 1.0) if self.level_length > 0 else 0
        
        # Draw UI
        self.renderer.draw_ui(progress, self.attempts, self.level_name)
        
        # Draw game over or level complete overlay
        if self.game_over:
            if self.level_complete:
                self.renderer.draw_level_complete()
            else:
                self.renderer.draw_game_over()
        
        pygame.display.flip()
    
    def run(self):
        """Main game loop"""
        while self.running:
            self.handle_input()
            self.update()
            self.draw()
            self.clock.tick(60)  # 60 FPS
        
        pygame.quit()
        sys.exit()


def main():
    """Entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Geometry Dash')
    parser.add_argument('--level', type=str, default='level_01',
                       help='Level ID to load (default: level_01)')
    
    args = parser.parse_args()
    
    game = GeometryDash(args.level)
    game.run()


if __name__ == "__main__":
    main()

