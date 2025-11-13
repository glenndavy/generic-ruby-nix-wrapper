# Generic ruby wrapper and flake 

## Purpose

The goal of this projet is to make available 2 generic tools for using ruby on nixos.

One is a flake that can be copied in and tweaked with project specifics. 

The other is a wrapper we can template from to be able to create a nixos wrapper.

The idea of these is that they provide an isolated environment, running its own ruby and its own gems, isloated from other rubies and gems on the system.

This solves various issues, but including where ruby 3.1.0 and 3.1.2 might call gems compiled against the other breaking linking.

Another desirable product of this repo would be a way to make a module for a ruby app, that can then be included in other configurations and configured declaratively.



