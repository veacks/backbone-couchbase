Q = require "q"
uuid = require "node-uuid"
couchbase = require "couchbase"
ViewQuery = couchbase.ViewQuery
N1qlQuery = couchbase.N1qlQuery

_ = require "underscore"
async = require "async"
Backbone = require "backbone"

N1qlIndexesChecker = require "./N1qlIndexesChecker"

###
# Set up the join functionally at the Backbone Collection level
# @param {object} [options={}] - Options for the fetch method
###
_originalCollectionFetch = Backbone.Collection::fetch
Backbone.Collection::fetch = (options) ->
  options = if options then _.clone(options) else {}

  # Check if join is required
  if options.join? and options.join is true or typeof options.join is "function"
    # Save the success method
    success = options.success
    # Overload success callback to perform join on each join
    options.success = (resp) =>
      tasks = []
      @each (model) ->
        tasks.push (aCb) ->
          model.fetch
            join: if options.join is true and model.join? then true else if typeof options.join is "function" then options.join
            success: ->
              aCb()
            error: (model, error) ->
              aCb error

      async.parallel tasks, (error) =>
        if success?
          success.call options.context, @, resp, options

  _originalCollectionFetch.apply @, [options]

###
# Create a Couchbase Sync Method for Backbone Models and Collections
# @param {object} [options={}] - Options for the creation of the sync method
# @option {object} bucket - Bucket object for the synchronisation
# @option {object} connection - Cluster address, bucket name and password
# @option {string} [sep="::"] - Replace "/" by separator, if false the url wont be formated
# @option {boolean} [httpError=false] - Format couchbase error to http friendly status
# @return {function} Backbone Couchbase Sync function
###
module.exports = (options = {}) ->
  ###
  # Format the document keys
  # @private
  ###
  _keysFormat = (url, ids) ->
    uList = []
    uList.push _keyFormat url+"/"+id for id in ids
    #console.log uList
    uList

  ###
  # Format the document key
  # @private
  ###
  _keyFormat = (url) ->
    url = decodeURIComponent url
    url = url.replace /^(\/)/, ''
    url = url.replace  /\//g, sep

  ###
  # Format couchbase error to http friendly
  # @private
  ###
  _couchbaseErrorFormat = (error, result) ->
    # if error is false, dont format error
    unless httpError
      return error
    
    switch error.code
      when 13
        return {
          status: 404
          message: error.toString()
        }
      when 12
        return {
          status: 409
          message: error.toString()
        }
      else
        return {
          status: 500
          message: result || error
        }

  ###
  # Generate the Backbone Sync Method
  # @param {string} method - CRUD command
  # @param {object} model - Backbone Model or Collection object
  # @param {object} options - Sync options
  # @option {callback~Error} error - Callback error
  # @option {callback~Success} success - Callback success 
  # @option {boolean} trace - Trace Couchbase process
  # @option {boolean} create - Force creation with a specific key 
  # @return promise
  ###
  _syncMethod = (method, model, options) ->
    def = Q.defer()

    ###
    # Send the success response
    # @private
    ###
    _success = (response) ->
      if options.success?
        options.success response
      def.resolve response

    ###
    # Send the error response
    # @private
    ###
    _error = (err) ->
      if options? and options.error?
        options.error _couchbaseErrorFormat err
      def.reject _couchbaseErrorFormat err
    
    ###
    # N1ql indexes
    ###
    _
    
    _ensureIndexes = (indexes) ->

    # Set reduced view to false
    reducedView = false
    ###
    # Callback to get the updated datas
    # @private
    ###
    couchbase_callback = (err, result) ->
      def.promise.cbError = err
      def.promise.cbResult = result
      
      # Trace insertion
      if options.trace
        console.log "  - method:"
        console.log method
        console.log "  - id:"
        switch typeof model.url
          when "function" then console.log _keyFormat(model.url())
          when "string" then console.log model.url
        console.log options
        console.log "  - result:"
        console.log result

      # If there is an error in the request
      if err? and (err isnt 0 or err.length? and err.length > 0)
        unless options.ids?
          # Send the error
          _error err
        else
          _error err, result
        if options.trace
          console.log "  - err:"
          console.log err
        return

      # If collection result
      if _.isArray result
        if reducedView
          response = if result[0]? then result[0].value else 0
        else
          response = []
          response.push item.value for item in result
      else if options.ids?
        response = []
        response.push item.value for id, item of result
      # Else if model
      else
        response = result.value

      # If model have a join method and join is required
      if options.join is true and model.join? 
        # Perform the join
        model.join response, (err, joinedDatas) ->
          if err?
            _error err
          else
            _success joinedDatas
        return
      else if typeof options.join is "function"
        options.join model, response, (err, joinedDatas) ->
          if err?
            _error err
          else
            _success joinedDatas
        return
      # Else send response
      _success response

      if options.trace
        console.log "  - response:"
        console.log response
        console.log "-----"

    if options.trace
        console.log "-----"
        console.log "Backbone Couchbase:"
        console.log " - method:"
        console.log method
    # Create a new object
    if method is "create" or (options.create? and options.create)
      model.set model.idAttribute, uuid.v4() if model.isNew()
      bucket.insert _keyFormat(model.url()), model.toJSON(), (err, result) ->
        if err?
          couchbase_callback err, result
          return false

        bucket.get _keyFormat(model.url()), couchbase_callback

    # Update an existing object
    else if method is "update" and (not options.create? or not options.create)
      bucket.replace _keyFormat(model.url()), model.toJSON(), (err, result) ->
        if err?
          couchbase_callback err, result
          return false

        bucket.get _keyFormat(model.url()), couchbase_callback

    # Read model or a collection
    else if method is "read"
      # Read collection bu multiget when model ids are setup
      if model.models? and options.ids?
        # If the id is a string, convert to array in case of only one id is wanted
        if typeof options.ids is "string"
          options.ids = [options.ids]
        # In case of its not an array
        unless _.isArray options.ids
          # Throw an error
          _error new Error "options.ids must be a String or an Array!"
        else
          # Format the keys
          formatedIds = _.map options.ids, (id) ->
            # If a model have been set to the collection
            if model.model?
              # Create a temporary model to format the id url
              tempModel = new model.model()
              # If id is object (for compound urlRoots methods)
              if _.isObject id
                # Index all the object
                tempModel.set id
              else
                # index the id as idAttribute
                tempModel.set tempModel.idAttribute, id
              # Return the formated key
              return _keyFormat(tempModel.url())
            # If there is no model
            # If the model url is a function
            return _keyFormat("#{model.url()}/#{id}") if _.isFunction model.url
            # If the model url is a string
            return _keyFormat("#{model.url}/#{id}")

          # Get a collection from a list of ids
          bucket.getMulti formatedIds, couchbase_callback

      # Read collection multiget when document ids are setup
      else if model.models? and options.docIds?
        bucket.getMulti options.docIds, couchbase_callback

      # Read model or a collection by design document
      else if model.type is "designDocument"
        designDocuement = model.designDocument || model.url.split("/")[0]
        viewName = model.viewName || model.url.split("/")[1]

        # Read a query
        query = ViewQuery.from designDocuement, viewName
        query.custom(options.custom) if options.custom?
        query.full_set(options.full_set) if options.full_set?
        query.group(options.group) if options.group?
        query.group_level(options.group_level) if options.group_level?
        query.id_range(options.id_range.start, options.id_range.end) if options.id_range?
        query.include_docs(options.include_docs) if options.include_docs?
        query.key(options.key) if options.key?
        query.keys(options.keys) if options.keys?
        query.limit(options.limit) if options.limit?
        query.on_error(options.on_error) if options.on_error?
        query.range(options.range.start, options.range.end, options.inclusiveEnd) if options.range?
        query.order(options.order) if options.order?
        
        # If a model asking for query, implement with a reduce
        if (not model.models? and not options.reduce?) or options.reduce
          reducedView = true
          query.reduce(true)
        else
          query.reduce(false)


        query.skip(skip) if options.skip?
        # If stale is false, it waits for the last elements to be indexed
        query.stale options.stale if options.stale?#|| ViewQuery.Update.BEFORE#ViewQuery.Update.BEFORE ViewQuery.Update.NONE ViewQuery.Update.AFTER

        # Run the query
        bucket.query query, couchbase_callback
      
      # Read model or collection by N1ql
      else if model.type is "N1ql"
        # Check if all required indexes exists and create them if not
        N1qlIndexesChecker bucket, model.indexes || [], (err) ->

          # Perform N1QL query
          query = N1qlQuery.fromString model.url()
          if options.params?
            bucket.query query, options.params, couchbase_callback
          else
            bucket.query query, couchbase_callback
      # Get data by simple key get
      else
        bucket.get _keyFormat(model.url()), couchbase_callback

    # Patch an object (edit only partialy)
    else if method is "patch"
      bucket.get _keyFormat(model.url()), (err, result) ->
        if err?
          couchbase_callback err, result
          return

        dbModel = result.value

        _.extend dbModel, model.toJSON()

        bucket.replace  _keyFormat(model.url()), dbModel, (err, result) ->
          if err?
            couchbase_callback err, result
            return false
          
          bucket.get _keyFormat(model.url()), couchbase_callback

    # Delete an object
    else if method is "delete"
      bucket.remove  _keyFormat(model.url()), couchbase_callback
    else
      # Send an error if method isnt reconised
      couchbase_callback { code: 500, message: "#{method}: Wrong or empty method for Backbone-Couchbase-Sync" }

    # Trigger request event is case of listening
    model.trigger 'request', model, def.promise, options
    # Return the promise
    return def.promise

  ###
  # Set up and check the bucket connection
  ###
  def = Q.defer()

  # Check if bucket or connections are present
  unless options.bucket? or options.connection?
    throw new Error "Bucket or Connection object is required to generate sync method"

  # Check the views and inject/update them when needed
  _viewsChecker = ->
    dbm = bucket.manager()
    if options.designDocuments?
      checkDesignDoc = (designDocName, callback) ->
        # Get server design document
        dbm.getDesignDocument designDocName, (err, serverDesignDoc) ->
          # If there is some error finding the design document
          if err?
            # If the design document doesnt exist on the server
            if err.message is "missing" or err.message is "not_found" or err.message is "deleted"
              # Insert the design document
              dbm.insertDesignDocument designDocName, options.designDocuments[designDocName], (err) ->
                if err? then callback(err) else callback()
            else
              #If another error
              callback err
            return

          # If the Deign Document version on server isnt up to date
          unless _.isEqual serverDesignDoc, options.designDocuments[designDocName]
            #console.warn "Replaced the Couchbase Design Document called \"#{viewName}\""
            # Then set the local one
            dbm.upsertDesignDocument designDocName, options.designDocuments[designDocName], (err) ->
              if err? then callback(err) else callback()
            return
          callback()
      # Check all design documents
      async.map Object.keys(options.designDocuments), checkDesignDoc, (err) ->
        if err?
          def.reject err
          return

        # Resolve by returning the sync method
        def.resolve _syncMethod

      return
    # Resolve by returning the sync method
    def.resolve _syncMethod

  # Assign bucket injected bucket
  if options.bucket?
    bucket = options.bucket
    _viewsChecker()

  # Create bucket with conf datas
  else if options.connection?
    # Retrun an error if cluster or bucket parameters are missing
    unless options.connection.cluster? and options.connection.bucket?
      throw new Error "Connection bucket and cluster are required"

    cluster = new couchbase.Cluster options.connection.cluster

    ###
    # Connection callback
    ###
    connectionCb = (err) ->
      if err?
        def.reject err
        return
      _viewsChecker()

    if options.connection.password?
      bucket = cluster.openBucket options.connection.bucket, options.connection.password, connectionCb
    else
      bucket = cluster.openBucket options.connection.bucket, connectionCb
  
  # Error formating
  httpError = options.httpError || true
  # Separator
  sep = options.sep || "::"
  # Id generator
  idGen = options.idGen || uuid
  
  return def.promise