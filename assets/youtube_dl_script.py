#!/usr/bin/env python3
# Simple Python script to extract YouTube audio URLs
# This is used as a fallback when yt-dlp or youtube-dl is not available

import sys
import json
import re
import urllib.request
import urllib.parse

def extract_player_response(html):
    # Extract the ytInitialPlayerResponse from the HTML
    pattern = r'ytInitialPlayerResponse\s*=\s*({.+?});'
    match = re.search(pattern, html)
    if match:
        try:
            return json.loads(match.group(1))
        except json.JSONDecodeError:
            return None
    return None

def extract_streaming_url(player_response):
    # Extract streaming URL from player response
    if not player_response:
        return None
    
    # Check for streaming data
    if 'streamingData' not in player_response:
        return None
    
    # First check adaptive formats (usually higher quality)
    formats = player_response['streamingData'].get('adaptiveFormats', [])
    
    # If no adaptive formats, try regular formats
    if not formats:
        formats = player_response['streamingData'].get('formats', [])
    
    # Find audio-only formats
    audio_formats = [f for f in formats if 'audio' in f.get('mimeType', '')]
    
    # If no audio-only formats, use any format
    if not audio_formats:
        audio_formats = formats
    
    # Sort by bitrate (highest first)
    audio_formats.sort(key=lambda x: x.get('bitrate', 0), reverse=True)
    
    # Get the URL from the best format
    for format in audio_formats:
        if 'url' in format:
            return format['url']
    
    return None

def get_video_url(video_id):
    # Construct the video URL
    url = f"https://www.youtube.com/watch?v={video_id}"
    
    try:
        # Set up request with user agent
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        }
        req = urllib.request.Request(url, headers=headers)
        
        # Get the HTML
        with urllib.request.urlopen(req) as response:
            html = response.read().decode('utf-8')
        
        # Extract player response
        player_response = extract_player_response(html)
        
        # Get streaming URL
        streaming_url = extract_streaming_url(player_response)
        
        if streaming_url:
            return streaming_url
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
    
    return None

if __name__ == "__main__":
    # Check arguments
    if len(sys.argv) < 2:
        print("Usage: python youtube_dl_script.py VIDEO_ID", file=sys.stderr)
        sys.exit(1)
    
    # Get video ID from arguments
    video_id = sys.argv[1]
    
    # Get streaming URL
    streaming_url = get_video_url(video_id)
    
    # Print the URL to stdout
    if streaming_url:
        print(streaming_url)
        sys.exit(0)
    else:
        sys.exit(1) 