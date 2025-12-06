"""
Geometry Dash - Main Game File
Loads and processes level YAML configurations
"""

import yaml
import os
from pathlib import Path
from typing import Dict, List, Any


class LevelLoader:
    """Loads and parses level YAML configuration files"""
    
    def __init__(self, levels_dir: str = None):
        """
        Initialize the level loader
        
        Args:
            levels_dir: Path to the levels directory. Defaults to ../levels
        """
        if levels_dir is None:
            # Get the directory of this file and navigate to levels
            current_dir = Path(__file__).parent
            levels_dir = current_dir.parent / "levels"
        
        self.levels_dir = Path(levels_dir)
        
    def load_level(self, level_id: str) -> Dict[str, Any]:
        """
        Load a level configuration from YAML file
        
        Args:
            level_id: Level identifier (e.g., "level_01")
            
        Returns:
            Dictionary containing the parsed level configuration
        """
        level_file = self.levels_dir / f"{level_id}.yml"
        
        if not level_file.exists():
            raise FileNotFoundError(f"Level file not found: {level_file}")
        
        with open(level_file, 'r') as f:
            level_data = yaml.safe_load(f)
        
        return level_data
    
    def list_levels(self) -> List[str]:
        """
        List all available level files
        
        Returns:
            List of level IDs (without .yml extension)
        """
        levels = []
        for file in self.levels_dir.glob("*.yml"):
            levels.append(file.stem)
        return sorted(levels)
    
    def get_level_metadata(self, level_id: str) -> Dict[str, Any]:
        """
        Get only the metadata for a level (without loading full config)
        
        Args:
            level_id: Level identifier
            
        Returns:
            Dictionary containing level metadata
        """
        level_data = self.load_level(level_id)
        return level_data.get('metadata', {})
    
    def get_level_objects(self, level_id: str) -> Dict[str, Any]:
        """
        Get all objects from a level configuration
        
        Args:
            level_id: Level identifier
            
        Returns:
            Dictionary containing all level objects organized by type
        """
        level_data = self.load_level(level_id)
        return level_data.get('objects', {})
    
    def get_level_settings(self, level_id: str) -> Dict[str, Any]:
        """
        Get level settings (player start, theme, etc.)
        
        Args:
            level_id: Level identifier
            
        Returns:
            Dictionary containing level settings
        """
        level_data = self.load_level(level_id)
        return level_data.get('settings', {})


class LevelProcessor:
    """Processes level data for game engine consumption"""
    
    def __init__(self, level_data: Dict[str, Any]):
        """
        Initialize with level data
        
        Args:
            level_data: Parsed level configuration dictionary
        """
        self.level_data = level_data
        self.metadata = level_data.get('metadata', {})
        self.settings = level_data.get('settings', {})
        self.objects = level_data.get('objects', {})
        self.sync_points = level_data.get('sync_points', [])
    
    def get_player_start(self) -> Dict[str, Any]:
        """Get player starting configuration"""
        return self.settings.get('player', {})
    
    def get_all_obstacles(self) -> List[Dict[str, Any]]:
        """Get all obstacles that can kill the player"""
        obstacles = []
        
        # Static obstacles
        obstacles.extend(self.objects.get('obstacles', []))
        
        # Moving platforms can also be obstacles if they're in the way
        # (implementation depends on game logic)
        
        return obstacles
    
    def get_all_platforms(self) -> List[Dict[str, Any]]:
        """Get all platforms the player can land on"""
        platforms = []
        
        # Static platforms
        platforms.extend(self.objects.get('platforms', []))
        
        # Moving platforms
        platforms.extend(self.objects.get('moving_platforms', []))
        
        return platforms
    
    def get_all_collectibles(self) -> List[Dict[str, Any]]:
        """Get all collectible items"""
        collectibles = []
        collectibles_data = self.objects.get('collectibles', {})
        
        # Handle case where collectibles might be None or not a dict
        if collectibles_data is None:
            collectibles_data = {}
        if not isinstance(collectibles_data, dict):
            return collectibles
        
        # Stars
        collectibles.extend(collectibles_data.get('stars', []))
        
        # Coins
        collectibles.extend(collectibles_data.get('coins', []))
        
        return collectibles
    
    def get_all_portals(self) -> List[Dict[str, Any]]:
        """Get all portals"""
        portals = []
        portals_data = self.objects.get('portals', {})
        
        # Handle case where portals might be None or not a dict
        if portals_data is None:
            portals_data = {}
        if not isinstance(portals_data, dict):
            return portals
        
        # Mode portals
        portals.extend(portals_data.get('mode_portals', []))
        
        # Speed portals
        portals.extend(portals_data.get('speed_portals', []))
        
        # Gravity portals
        portals.extend(portals_data.get('gravity_portals', []))
        
        # Size portals
        portals.extend(portals_data.get('size_portals', []))
        
        # Teleport portals
        portals.extend(portals_data.get('teleport_portals', []))
        
        return portals
    
    def get_level_length(self) -> float:
        """Get the total length of the level"""
        return self.settings.get('level', {}).get('length', 0)
    
    def get_theme_colors(self) -> Dict[str, str]:
        """Get theme color configuration"""
        return self.settings.get('theme', {})
    
    def get_music_config(self) -> Dict[str, Any]:
        """Get music configuration"""
        return self.settings.get('music', {})
    
    def get_end_zone(self) -> Dict[str, Any]:
        """Get level end zone configuration"""
        return self.settings.get('level', {}).get('end_zone', {})


# Example usage
if __name__ == "__main__":
    # Initialize level loader
    loader = LevelLoader()
    
    # List available levels
    print("Available levels:")
    for level_id in loader.list_levels():
        print(f"  - {level_id}")
    
    # Load first level
    if loader.list_levels():
        level_id = loader.list_levels()[0]
        print(f"\nLoading level: {level_id}")
        
        level_data = loader.load_level(level_id)
        processor = LevelProcessor(level_data)
        
        # Display level info
        print(f"Name: {processor.metadata.get('name')}")
        print(f"Difficulty: {processor.metadata.get('difficulty')}")
        print(f"Length: {processor.get_level_length()} pixels")
        
        # Display object counts
        print(f"\nObjects:")
        print(f"  Platforms: {len(processor.get_all_platforms())}")
        print(f"  Obstacles: {len(processor.get_all_obstacles())}")
        print(f"  Collectibles: {len(processor.get_all_collectibles())}")
        print(f"  Portals: {len(processor.get_all_portals())}")
        
        # Display player start
        player_start = processor.get_player_start()
        print(f"\nPlayer Start:")
        print(f"  Position: ({player_start.get('start_x')}, {player_start.get('start_y')})")
        print(f"  Mode: {player_start.get('start_mode')}")
        print(f"  Speed: {player_start.get('start_speed')}")

