Q = require "q"
uuid = require "node-uuid"
couchbase = require "couchbase"
ViewQuery = couchbase.ViewQuery

module.exports = (bucket, sep = "::") ->
  return sync = (method, model, options) ->
    def = Q.defer()

    couchbase_callback = (err, result) ->
      if err?
        if options? and options.error?
          options.error err
        def.reject err
        return

      if options? and options.success?
        options.success result
      def.resolve result

    unless model.prefix?
      err = "Model must have a prefix."
      if options? and options.error?
        options.error err
      def.reject err

    else
      switch method
        when "create"
          modelId = uuid.v4()

          datas = model.toJSON()
          datas[model.idAttribute] = modelId

          bucket.insert "#{model.prefix}#{sep}#{modelId}", datas, couchbase_callback

        when "update"
          bucket.replace _url(model.url()), model.toJSON(), couchbase_callback

        when "read"
          # Read collection
          if model.models?
            query = ViewQuery.from options.designDocument || model.designDocument, options.viewName || model.viewName
            query.custom options.custom if options.custom?
            bucket.query query, couchbase_callback
          # Read model
          else
            bucket.get "#{model.prefix}#{sep}#{model.id}", couchbase_callback

        when "patch"
          bucket.get _url(model.url()), (err, result) ->
            if err?
              cb err
              return

            dbModel = result.value

            _.extend dbModel, model.toJSON()

            bucket.replace  "#{model.prefix}#{sep}#{model.id}", dbModel, couchbase_callbackw

        when "delete"
          bucket.remove  "#{model.prefix}#{sep}#{model.id}", couchbase_callback

    return def.promise