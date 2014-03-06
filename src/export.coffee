_         = require("lodash")
b         = require("ast-types").builders
escodegen = require("escodegen")
through   = require("through2")

module.exports = fixModule = (options = {}) ->

  options = _.defaults(options,
    sourceMap : false
    wrapShim : true
  )

  through.obj( (module, enc, done) ->

    if module.isShallow
      done()
      return

    ast = module.file.ast

    if not module.hasDefine
      
      ast.body.push(
        b.expressionStatement(
          b.callExpression(
            b.identifier("define")
            [
              b.literal(module.name)
              b.arrayExpression(module.deps.map( (dep) -> b.literal(dep.name) ))
              b.functionExpression(
                null
                []
                b.blockStatement([
                  b.returnStatement(
                    if module.exports
                      b.identifier(module.exports)
                    else
                      null
                  )
                ])
              )
            ]
          )
        )
      )
    
    else if module.isAnonymous

      module.astNodes.forEach((astNode) ->
        if astNode.callee.name == "define" and 0 < astNode.arguments.length < 3 and astNode.arguments[0].type != "Literal"
          
          astNode.arguments = [
            b.literal(module.name)
            b.arrayExpression(module.deps.map( (dep) -> b.literal(dep.name) ))
            _.last(astNode.arguments)
          ]
      )

    # TODO: Handle shimmed, mapped and relative deps

    # console.log escodegen.generate(module.file.ast, sourceMap : true).toString()
    

    if options.sourceMap
      generatedCode = escodegen.generate(
        ast
        sourceMap : true, sourceMapWithCode : true
      )

      sourceFile = module.file.clone()
      sourceFile.contents = new Buffer(generatedCode.code, "utf8")

      sourceMapFile = module.file.clone()
      sourceMapFile.path += ".map"
      sourceMapFile.contents = new Buffer(generatedCode.map.toString(), "utf8")

      @push(sourceFile)
      @push(sourceMapFile)

    else
      sourceFile = module.file.clone()
      sourceFile.contents = new Buffer(escodegen.generate(ast), "utf8")

      @push(sourceFile)

    done()

  )