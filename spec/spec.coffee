# Assertion and mock frameworks
chai = require "chai"
should = chai.should()

sinon = require "sinon"

# Required modules
couchbase = require "couchbase"
Backbone = require "backbone"
backboneCouchbase = require "../index"

# Set up db mock for CI
mock = couchbase.Mock

describe "Couchbase connection", ->

  describe "Bucket object injection", ->

    it "should create a sync method connected to a specific bucket", (done) ->
      cluster = new mock.Cluster "127.0.0.1:8091"
      bucket = cluster.openBucket "testBucket", (err) ->
        sync = backboneCouchbase { bucket: bucket }
        sync.should.be.a "function"
      done()

    it "Should throw an error when there is no bucket in options and no connection setup", (done) ->
      try
        sync = backboneCouchbase()
      catch e
        e.should.be.an "error"
        e.message.should.be.equal "Bucket or Connection object is required to generate sync method"
      done()

  describe "Bucket params connection", ->

    it "Should create a bucket connection when there is a connection setup", (done) ->
      sync = backboneCouchbase
        connection:
          cluster: "127.0.0.1:8091"
          bucket: "testBucket"
          password: "password"

      sync.should.be.a "function"
      done()

    it "Should throw an error when missing connection parameters", (done) ->
      try
        sync = backboneCouchbase
          connection:
            bucket: "testBucket"
            password: "password"

        sync = backboneCouchbase
          connection:
            cluster: "127.0.0.1:8091"
            password: "password"
      catch e
        e.should.be.an "error"
        e.message.should.be.equal "Connection bucket and cluster are required"
        # Todo: connection error
      done()

  it "Should return an error when bucket isnt connected", (done) ->
    sync = backboneCouchbase
    done()

  ###
  describe "Automatic key generation", ->

    it "Should create an GUID key by default", (done) ->
      done()

    it "Should create a custom ID key when a custom id key gen is setup in options", (done) ->
      done()
  ###

describe "Create", ->

  it "Should create a document with a GUID when saving a Model", (done) ->
    testModel = Backbone.Model.extend {}
    testModel::sync = backboneCouchbase
      bucket: @bucket

    testModel.set "test", "yes"


    testModel.save()
    .fail( (error) ->
      error.should.be.empty
    )
    .done( (model) ->
      model.get("test").should.be.equal "yes"
      done()
    )

  it "Should check model's \"idAttribute\" to set the id", (done) ->
    done()

  it "Should force saving a document when saving a Model which already have an ID and keep the ID as document key", (done) ->
    done()

  it "Should return an error when the model ID already exist in bucket", (done) ->
    done()

describe "Update", ->

  it "Should check model's \"idAttribute\" to get the id", (done) ->
    done()

  it "Should update a model when model ID already exist in bucket", (done) ->
    done()

  it "Should return an error when model ID doesn't exist in bucket", (done) ->
    done()

describe "Patch", ->

  it "Should check model's \"idAttribute\" to get the id", (done) ->
    done()

  it "Should update a model when model ID already exist in bucket", (done) ->
    done()

  it "Should return an error when model ID doesn't exist in bucket", (done) ->
    done()

describe "Destroy", ->

  it "Should check model's \"idAttribute\" to get the id", (done) ->
    done()

  it "Should destroy a model when model ID already exist in bucket", (done) ->
    done()

  it "Should return an error when model ID doesn't exist in bucket", (done) ->
    done()

describe "Fetch Model", ->

  it "Should check model's \"idAttribute\" to get the id", (done) ->
    done()

  it "Should return the model datas when model ID already exist in bucket", (done) ->
    done()

  it "Should return an error when model ID doesn't exist in bucket", (done) ->
    done()

describe "Fetch Collection", ->

  it "Should return an error if design document name (collection.url) isnt setup", (done) ->
    done()

  it "Should return an error if design document doesn't exist in bucket", (done) ->
    done()

  it "Should return an error if collection.defaultView or option.viewName isnt defined", (done) ->
    done()

  it "Should return the models datas", (done) ->
    done()

describe "Sync integration", ->

  describe "Global sync (rewrite the Backbone.sync)", ->

    it "Should rewrite the sync to assign a global bucket to backbone", (done) ->
      done()

  describe "Specific sync (rewrite model.prototype.sync or collection.prototype.sync)", ->

    it "Should rewrite the sync to a specif bucket for only one model", (done) ->
      done()

    it "Should rewrite the sync to a specific bucket for only one collection", (done) ->
      done()

  describe "Separator", ->

    it "Should replace the slash \"/\" separator by a double coma \"::\" by default", (done) ->
      done()

    it "Should replace the slash \"/\" separator by a custom separator when setup in options", (done) ->
      done()