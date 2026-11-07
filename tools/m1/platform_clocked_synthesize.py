"""Synthesize the full platform with the actual common-source clock IP."""
from platform_elaborate import main

if __name__ == '__main__':
    main(synthesize=True, clocked=True)
