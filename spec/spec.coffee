# Assertion and mock frameworks
chai = require "chai"
should = chai.should()
sinon = require "sinon"
sinonChai = require "sinon-chai"
chai.use sinonChai

# Required modules
async = require "async"
couchbase = require "couchbase"
Backbone = require "backbone"
backboneCouchbase = require "../src/index"

# Set up db mock for CI
mock = couchbase.Mock

describe "Couchbase connection", ->

  describe "Bucket object injection", ->

    it "should create a sync method connected to a specific bucket", (done) ->
      cluster = new mock.Cluster "127.0.0.1:8091"
      bucket = cluster.openBucket "testBucket"
      sync = backboneCouchbase { bucket: bucket }
      sync.should.be.a "function"
      done()

    it "Should throw an error when there is no bucket in options and no connection setup", (done) ->
      #err = new Error "Bucket or Connection object is required to generate sync method"
      (-> backboneCouchbase()).should.throw "Bucket or Connection object is required to generate sync method"
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
      ( -> backboneCouchbase
        connection:
          bucket: "testBucket"
          password: "password"
      ).should.throw  "Connection bucket and cluster are required"

      ( -> backboneCouchbase
        connection:
          cluster: "127.0.0.1:8091"
          password: "password"
      ).should.throw  "Connection bucket and cluster are required"
      done()

  ###
  it "Should return an error when bucket isnt connected", (done) ->
    sync = backboneCouchbase
    done()
  ###

  ###
  describe "Automatic key generation", ->

    it "Should create an GUID key by default", (done) ->
      done()

    it "Should create a custom ID key when a custom id key gen is setup in options", (done) ->
      done()
  ###

describe "Model CRUD and Collection fetch Operations", ->
  beforeEach (done) ->
    cluster = new mock.Cluster "0.0.0.0:8091"
    @bucket = cluster.openBucket "test", (err) ->
      throw err if err?
      done()

  afterEach (done) ->
    @bucket.disconnect()
    done()

  describe "Create", ->
    it "Should create a document with a GUID when saving a Model", (done) ->
      TestModel = Backbone.Model.extend {
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket
      
      testModel = new TestModel
        test: "yes"

      testModel.save null, {
        error: (model, error, options) ->
          done error.message

        success: (model, response, options) ->
          # Check UUID format
          response.id.should.match /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
          testModel.id.should.match /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
          done()
      }


    it "Should check model's \"idAttribute\" to set the id", (done) ->
      TestModel = Backbone.Model.extend {
        idAttribute: "ortherId"
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket

      testModel = new TestModel
        test: "yes"

      testModel.save null, {
        error: (model, error, options) ->
          done error.message

        success: (model, response, options) ->
          # Check UUID format
          testModel.id.should.match /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
          testModel.get("ortherId").should.match /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
          model.get("ortherId").should.match /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
          done()
      }

    it "Should force saving a document when saving a Model which already have an ID and keep the ID as document key", (done) ->
      TestModel = Backbone.Model.extend {
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket

      testModel = new TestModel
        id: "customId"
        test: "yes"

      testModel.save(null, { create: true })
      .fail( (error) ->
        done error
      )
      .done( (response) ->
        testModel.id.should.be.equal "customId"
        response.id.should.be.equal "customId"
        done()
      )

    it "Should return an error when the model ID already exist in bucket", (done) ->
      TestModel = Backbone.Model.extend {
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket

      testModel = new TestModel
        id: "customId"
        test: "yes"

      testModel.save null, {
        create: true
        error: (model, error, options) ->
          done error.message

        success: (response) ->
          SecoundModel = new TestModel
            id: "customId"
            test: "yes"

          SecoundModel.save null, {
            create: true
            error: (model, error, options) ->
              error.status.should.be.equal 409
              error.message.should.be.a("string")
              done()
            success: (model, response, options) -> 
              done(new Error "Should Fail!")
          }
      }

  describe "Update", ->
    it "Should update a model when model ID already exist in bucket", (done) ->
      TestModel = Backbone.Model.extend {
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket

      modelTasks = []

      insertedModel = new TestModel
        test: "ABCD"
      # Create and save a model
      modelTasks.push (aCb) ->
        insertedModel.save null, {
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            insertedModel.get("test").should.be.equal "ABCD"
            aCb()
        }

      # Update the model
      modelTasks.push (aCb) ->
        insertedModel.set "test", "DCBA"

        insertedModel.save null, {
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            insertedModel.get("test").should.be.equal "DCBA"
            aCb()
        }

      async.series modelTasks, (err) ->
        if err then done(err) else done()


    it "Should check model's \"idAttribute\" to get the id", (done) ->
      TestModel = Backbone.Model.extend {
        idAttribute: "otherId"
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket

      modelTasks = []

      insertedModel = new TestModel
        test: "ABCD"

      # Create and save a model
      modelTasks.push (aCb) ->
        insertedModel.save null, {
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            insertedModel.get("test").should.be.equal "ABCD"
            aCb()
        }

      updateTestModel = {}

      # Fetch model to update
      modelTasks.push (aCb) ->
        updateTestModel = new TestModel
          otherId: insertedModel.id

        updateTestModel.fetch {
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            model.get("test").should.be.equal "ABCD"
            aCb()
        }

      # Save entire model
      modelTasks.push (aCb) ->
        updateTestModel.set { test: "DCBA" }
        updateTestModel.save null, {
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            model.get("test").should.be.equal "DCBA"
            aCb()
        }

      async.series modelTasks, (err) ->
        if err then done(err) else done()

    it "Should return an error when model ID doesn't exist in bucket", (done) ->
      TestModel = Backbone.Model.extend {
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket

      updateTestModel = new TestModel
          id: "fakeId"
          test: "ABCD"

      updateTestModel.save null, {
        error: (model, error, options) ->
          error.status.should.be.equal 404
          error.message.should.be.a "string"
          done()

        success: (model, response, options) ->
          done(new Error "Should Fail!")
      }

  describe "Patch", ->

    it "Should update a model when model ID already exist in bucket", (done) ->
      TestModel = Backbone.Model.extend {
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket

      modelTasks = []

      insertedModel = new TestModel
        test: "ABCD"
        testToPatch: "EFGH"

      # Create and save a model
      modelTasks.push (aCb) ->
        insertedModel.save null, {
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            insertedModel.get("test").should.be.equal "ABCD"
            aCb()
        }

      # Update the model
      modelTasks.push (aCb) ->
        pachedModel = new TestModel
          id: insertedModel.id

        pachedModel.set "testToPatch", "HGFE"

        pachedModel.save null, {
          patch: true
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            pachedModel.get("test").should.be.equal "ABCD"
            pachedModel.get("testToPatch").should.be.equal "HGFE"
            aCb()
        }

      async.series modelTasks, (err) ->
        if err then done(err) else done()

    it "Should check model's \"idAttribute\" to get the id", (done) ->
      TestModel = Backbone.Model.extend {
        idAttribute: "otherId"
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket

      modelTasks = []

      insertedModel = new TestModel
        test: "ABCD"
        testToPatch: "EFGH"

      # Create and save a model
      modelTasks.push (aCb) ->
        insertedModel.save null, {
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            insertedModel.get("test").should.be.equal "ABCD"
            aCb()
        }

      # Update the model
      modelTasks.push (aCb) ->
        pachedModel = new TestModel
          otherId: insertedModel.id

        pachedModel.set "testToPatch", "HGFE"

        pachedModel.save null, {
          patch: true
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            pachedModel.get("test").should.be.equal "ABCD"
            pachedModel.get("testToPatch").should.be.equal "HGFE"
            aCb()
        }

      async.series modelTasks, (err) ->
        if err then done(err) else done()

    it "Should return an error when model ID doesn't exist in bucket", (done) ->
      TestModel = Backbone.Model.extend {
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket

      insertedModel = new TestModel
        id: "fakeId"
        test: "ABCD"
        testToPatch: "EFGH"

      insertedModel.save null, {
        patch: true
        error: (model, error, options) ->
          error.status.should.be.equal 404
          error.message.should.be.a "string"
          done()

        success: (model, response, options) ->
          done(new Error "Should Fail!")
      }

  describe "Destroy", ->

    it "Should destroy a model when model ID already exist in bucket", (done) ->
      TestModel = Backbone.Model.extend {
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket

      modelTasks = []

      insertedModel = new TestModel
        test: "ABCD"
        testToPatch: "EFGH"

      # Create and save a model
      modelTasks.push (aCb) ->
        insertedModel.save null, {
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            insertedModel.get("test").should.be.equal "ABCD"
            aCb()
        }

      # Update the model
      modelTasks.push (aCb) ->
        pachedModel = new TestModel
          id: insertedModel.id

        pachedModel.destroy {
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            aCb()
        }

      async.series modelTasks, (err) ->
        if err then done(err) else done()

    it "Should check model's \"idAttribute\" to get the id", (done) ->
      TestModel = Backbone.Model.extend {
        idAttribute: "otherId"
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket

      modelTasks = []

      insertedModel = new TestModel
        test: "ABCD"
        testToPatch: "EFGH"

      # Create and save a model
      modelTasks.push (aCb) ->
        insertedModel.save null, {
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            insertedModel.get("test").should.be.equal "ABCD"
            aCb()
        }

      # Update the model
      modelTasks.push (aCb) ->
        pachedModel = new TestModel
          otherId: insertedModel.id

        pachedModel.destroy {
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            aCb()
        }

      async.series modelTasks, (err) ->
        if err then done(err) else done()

    it "Should return an error when model ID doesn't exist in bucket", (done) ->
      TestModel = Backbone.Model.extend {
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket


      pachedModel = new TestModel
        id: "fakeId"

      pachedModel.destroy {
        error: (model, error, options) ->
          error.status.should.be.equal 404
          error.message.should.be.a "string"
          done()

        success: (model, response, options) ->
          done(new Error "Should Fail!")
      }

  describe "Fetch Model", ->

    it "Should return the model datas when model ID already exist in bucket", (done) ->
      TestModel = Backbone.Model.extend {
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket

      modelTasks = []

      insertedModel = new TestModel
        test: "ABCD"

      # Create and save a model
      modelTasks.push (aCb) ->
        insertedModel.save null, {
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            insertedModel.get("test").should.be.equal "ABCD"
            aCb()
        }

      # Update the model
      modelTasks.push (aCb) ->
        fetchedModel = new TestModel
          id: insertedModel.id

        fetchedModel.fetch {
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            insertedModel.get("test").should.be.equal "ABCD"
            aCb()
        }

      async.series modelTasks, (err) ->
        if err then done(err) else done()

    it "Should check model's \"idAttribute\" to get the id", (done) ->
      TestModel = Backbone.Model.extend {
        idAttribute: "otherId"
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket

      modelTasks = []

      insertedModel = new TestModel
        test: "ABCD"

      # Create and save a model
      modelTasks.push (aCb) ->
        insertedModel.save null, {
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            insertedModel.get("test").should.be.equal "ABCD"
            aCb()
        }

      # Update the model
      modelTasks.push (aCb) ->
        fetchedModel = new TestModel
          otherId: insertedModel.id

        fetchedModel.fetch {
          error: (model, error, options) ->
            aCb error.message

          success: (model, response, options) ->
            insertedModel.get("test").should.be.equal "ABCD"
            aCb()
        }

      async.series modelTasks, (err) ->
        if err then done(err) else done()

    it "Should return an error when model ID doesn't exist in bucket", (done) ->
      TestModel = Backbone.Model.extend {
        urlRoot: "test"
      }

      TestModel::sync = backboneCouchbase
        bucket: @bucket

      fetchedModel = new TestModel
        id: "fakeId"

      fetchedModel.fetch {
        error: (model, error, options) ->
          error.status.should.be.equal 404
          error.message.should.be.a "string"
          done()

        success: (model, response, options) ->
          done(new Error "Should Fail!")
      }

  describe "Model Multi Querry Joints", ->
    it "Developped but need to do the unit tests", (done) ->
      done(new Error "Todo: unit test")

  describe "Collection Multi Querry Joints", ->
    it "Developped but need to do the unit tests", (done) ->
      done(new Error "Todo: unit test")

  describe "Fetch Collection", ->
    it "Should return an error if design document name (collection.url) isnt setup", (done) ->
      TestCollection = Backbone.Collection.extend {}

      TestCollection::sync = backboneCouchbase
        bucket: @bucket
      
      done()

    it "Should return an error if design document doesn't exist in bucket", (done) ->
      done(new Error "Todo: unit test")

    it "Should return an error if collection.defaultView or option.viewName isnt defined", (done) ->
      done(new Error "Todo: unit test")

    it "Should return the models datas", (done) ->
      done(new Error "Todo: unit test")

  describe "N1QL Collection fetch", ->
    it "Need to be developped", (done) ->
      done(new Error "Todo: unit test")


describe "Sync integration", ->

  describe "Global sync (rewrite the Backbone.sync)", ->

    it "Should rewrite the sync to assign a global bucket to backbone", (done) ->
      done(new Error "Todo: unit test")

  describe "Specific sync (rewrite model.prototype.sync or collection.prototype.sync)", ->

    it "Should rewrite the sync to a specif bucket for only one model", (done) ->
      done(new Error "Todo: unit test")

    it "Should rewrite the sync to a specific bucket for only one collection", (done) ->
      done(new Error "Todo: unit test")

  describe "Separator", ->

    it "Should replace the slash \"/\" separator by a double coma \"::\" by default", (done) ->
      done(new Error "Todo: unit test")

    it "Should replace the slash \"/\" separator by a custom separator when setup in options", (done) ->
      done(new Error "Todo: unit test")