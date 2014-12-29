"use strict"
module.exports = watch = (grunt) ->
  
  # Load task
  grunt.loadNpmTasks "grunt-contrib-watch"

  {
    coffee:
      files: "src/**/*.coffee"
      tasks: ["coffee"]
  }