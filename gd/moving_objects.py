"""
Moving objects handler for Geometry Dash
Handles moving platforms and other animated objects
"""

from typing import Dict, Any, List


class MovingPlatform:
    """Represents a moving platform"""
    
    def __init__(self, platform_data: Dict[str, Any]):
        """Initialize moving platform from YAML data"""
        self.id = platform_data.get('id', '')
        self.type = platform_data.get('type', 'horizontal')
        self.x = platform_data.get('x', 0)
        self.y = platform_data.get('y', 0)
        self.width = platform_data.get('width', 150)
        self.height = platform_data.get('height', 30)
        self.color = platform_data.get('color', '#0f3460')
        
        # Movement configuration
        movement = platform_data.get('movement', {})
        self.pattern = movement.get('pattern', 'linear')
        self.start_x = movement.get('start_x', self.x)
        self.end_x = movement.get('end_x', self.x)
        self.start_y = movement.get('start_y', self.y)
        self.end_y = movement.get('end_y', self.y)
        self.speed = movement.get('speed', 2)
        self.loop = movement.get('loop', True)
        
        # Current movement state
        self.current_x = self.x
        self.current_y = self.y
        self.direction = 1  # 1 for forward, -1 for backward
        self.progress = 0.0  # 0.0 to 1.0
        
    def update(self):
        """Update platform position"""
        if self.pattern == 'linear':
            # Linear interpolation - speed is now progress per frame (0.0 to 1.0)
            if self.direction > 0:
                self.progress += self.speed
                if self.progress >= 1.0:
                    if self.loop:
                        self.progress = 0.0
                    else:
                        self.progress = 1.0
                        self.direction = -1
            else:
                self.progress -= self.speed
                if self.progress <= 0.0:
                    if self.loop:
                        self.progress = 1.0
                    else:
                        self.progress = 0.0
                        self.direction = 1
            
            # Interpolate position smoothly
            self.current_x = self.start_x + (self.end_x - self.start_x) * self.progress
            self.current_y = self.start_y + (self.end_y - self.start_y) * self.progress
        
        elif self.pattern == 'circular':
            # Circular movement (simplified)
            import math
            radius_x = abs(self.end_x - self.start_x) / 2
            radius_y = abs(self.end_y - self.start_y) / 2
            center_x = (self.start_x + self.end_x) / 2
            center_y = (self.start_y + self.end_y) / 2
            
            # Convert speed to radians per frame (assuming speed is 0.01-0.1 range)
            angular_speed = self.speed * 0.1  # Adjust multiplier for desired speed
            self.progress += angular_speed
            if self.progress >= 2 * math.pi:
                self.progress = 0.0
            
            self.current_x = center_x + radius_x * math.cos(self.progress)
            self.current_y = center_y + radius_y * math.sin(self.progress)
        
        elif self.pattern == 'sine':
            # Sine wave movement
            import math
            # Convert speed to radians per frame
            angular_speed = self.speed * 0.1
            self.progress += angular_speed
            if self.progress >= 2 * math.pi:
                self.progress = 0.0
            
            # Horizontal sine wave
            amplitude = abs(self.end_y - self.start_y) / 2
            self.current_x = self.start_x + (self.end_x - self.start_x) * (self.progress / (2 * math.pi))
            self.current_y = self.start_y + amplitude * math.sin(self.progress)
    
    def get_rect(self):
        """Get current platform rectangle"""
        import pygame
        return pygame.Rect(self.current_x, self.current_y, self.width, self.height)
    
    def get_data(self) -> Dict[str, Any]:
        """Get platform data in format expected by renderer"""
        return {
            'x': self.current_x,
            'y': self.current_y,
            'width': self.width,
            'height': self.height,
            'color': self.color,
            'type': 'platform'
        }


def create_moving_platforms(platforms_data: List[Dict[str, Any]]) -> List[MovingPlatform]:
    """Create MovingPlatform objects from YAML data"""
    moving_platforms = []
    for platform_data in platforms_data:
        moving_platforms.append(MovingPlatform(platform_data))
    return moving_platforms

