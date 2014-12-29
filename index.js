(function() {
  var Q, ViewQuery, couchbase, uuid, _;

  Q = require("q");

  uuid = require("node-uuid");

  couchbase = require("couchbase");

  ViewQuery = couchbase.ViewQuery;

  _ = require("underscore");

  module.exports = function(bucket, sep) {
    var _keyFormat;
    if (sep == null) {
      sep = "::";
    }
    _keyFormat = function(url) {
      url = decodeURIComponent(url);
      url = url.replace(/^(\/)/, '');
      return url = url.replace(/\//g, sep);
    };
    return function(method, model, options) {
      var couchbase_callback, def, query;
      def = Q.defer();
      couchbase_callback = function(err, result) {
        var response, _i, _len;
        if (options.trace) {
          console.log("-----");
          console.log("Backbone Couchbase:");
          console.log("  - method:");
          console.log(method);
          console.log("  - id:");
          console.log(_keyFormat(model.url()));
          console.log(options);
        }
        if (err != null) {
          if ((options != null) && (options.error != null)) {
            options.error(err);
          }
          def.reject(err);
          if (options.trace) {
            console.log("  - err:");
            console.log(err);
          }
          return;
        }
        if (_.isArray(result)) {
          response = [];
          for (_i = 0, _len = result.length; _i < _len; _i++) {
            model = result[_i];
            response.push(model.value);
          }
        } else {
          response = result.value;
        }
        if ((options != null) && (options.success != null)) {
          options.success(response);
        }
        def.resolve(response);
        if (options.trace) {
          console.log("  - response:");
          console.log(response);
          return console.log("-----");
        }
      };
      if (method === "create" || ((options.create != null) && options.create)) {
        if (model.isNew()) {
          model.set(model.idAttribute, uuid.v4());
        }
        bucket.insert(_keyFormat(model.url()), model.toJSON(), function(err, result) {
          if (err != null) {
            couchbase_callback(err, result);
            return false;
          }
          return bucket.get(_keyFormat(model.url()), couchbase_callback);
        });
      } else if (method === "update" && ((options.create == null) || !options.create)) {
        bucket.replace(_keyFormat(model.url()), model.toJSON(), function(err, result) {
          if (err != null) {
            couchbase_callback(err, result);
            return false;
          }
          return bucket.get(_keyFormat(model.url()), couchbase_callback);
        });
      } else if (method === "read") {
        if (model.models != null) {
          query = ViewQuery.from(model.url, options.viewName || model.defaultView);
          if (options.custom != null) {
            query.custom(options.custom);
          }
          bucket.query(query, couchbase_callback);
        } else {
          bucket.get(_keyFormat(model.url()), couchbase_callback);
        }
      } else if (method === "patch") {
        bucket.get(_keyFormat(model.url()), function(err, result) {
          var dbModel;
          if (err != null) {
            couchbase_callback(err, result);
            return;
          }
          dbModel = result.value;
          _.extend(dbModel, model.toJSON());
          return bucket.replace(_keyFormat(model.url()), dbModel, function(err, result) {
            if (err != null) {
              couchbase_callback(err, result);
              return false;
            }
            return bucket.get(_keyFormat(model.url()), couchbase_callback);
          });
        });
      } else if (method === "delete") {
        bucket.remove(_keyFormat(model.url()), couchbase_callback);
      } else {
        couchbase_callback({
          code: 500,
          message: "" + method + ": Wrong or empty method for Backbone-Couchbase-Sync"
        });
      }
      model.trigger('request', model, null, options);
      return def.promise;
    };
  };

}).call(this);
