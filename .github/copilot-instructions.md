# Coders of the Caribbean

## Project Scope
- This repository is for a CodinGame Coders of the Caribbean bot.
- No implementation language or build tooling has been established yet. Do not assume a stack or add dependencies unless needed for the requested task.

## Referee
- We prepare for a game where referee is not available, so don't attempt to get it from the internet, build it from scratch using the rules.
- The referee should allow to play games locally with very good performances.
- The absolute fidelity of the referee should be validated by comparing its outcomes with the expected results based on the games captured with the codingame API.
- An arena should be provided to facilitate matches between different bot versions using the local referee.
- The arena should support automated tournaments and provide detailed match results for analysis.
- The arena should be designed to easily integrate with different versions of the bot and the local referee.

## Arena Implementation
- The arena should provide a user-friendly interface to set up and run matches between different bot versions.
- The arena should support both single matches and tournament-style competitions.
- The arena should log detailed match results, including turn-by-turn actions and final outcomes, for analysis and debugging.
- The arena should be designed to easily integrate with the local referee and different bot versions.
- The arena should allow for automated testing and benchmarking of bot performance across multiple matches.
- There should be a graphical interface to visualize matches and their outcomes for better analysis and understanding.

## Bot Implementation
- Bot should be implemented in C++. Tell if you believe another language would be more suitable for certain parts of the implementation.
- Different versions of the bot should be able to compete against each other using the local referee.
- Different versions of the bot should be saved and versioned to allow for easy comparison and testing against the local referee.
- The bot should be designed to be easily configurable to test different strategies and parameters.
- A documentation file explaining the bot's design, strategies, and usage should be maintained to facilitate understanding and future development.