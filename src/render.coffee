###
# GLOBALS
###
poly.paper = (dom, w, h, handleEvent) ->
  if not Raphael?
    throw poly.error.depn "The dependency Raphael is not included."
  paper = Raphael(dom, w, h)
  # add click handler for clicking outside of things
  bg = paper.rect(0,0,w,h).attr('stroke-width', 0)
  bg.click handleEvent('reset')
  # add dragging handle for selecting
  handler = handleEvent('select')
  start = end = null
  onstart = () -> start = null; end = null
  onmove = (dx, dy, y, x) ->
    if start? then end = x:x, y:y else start = x:x, y:y
  onend = () -> if start? and end? then handler start:start, end:end
  bg.drag onmove, onstart, onend
  paper
###
Helper function for rendering all the geoms of an object
###
poly.render = (handleEvent, paper, scales, coord) -> (offset={}, clipping=false, mayflip=true) ->
  add: (mark, evtData, tooltip) ->
    if not coord.type?
      throw poly.error.unknown "Coordinate don't have at type?"
    if not renderer[coord.type]?
      throw poly.error.input "Unknown coordinate type #{coord.type}"
    if not renderer[coord.type][mark.type]?
      throw poly.error.input "Coord #{coord.type} has no mark #{mark.type}"

    pt = renderer[coord.type][mark.type].render paper, scales, coord, offset, mark, mayflip
    if clipping? then pt.attr('clip-rect', clipping)
    if evtData and _.keys(evtData).length > 0
      pt.data 'e', evtData
    if tooltip
      pt.data 't', tooltip
    pt.click handleEvent('click')
    pt.hover handleEvent('mover'), handleEvent('mout')
    pt
  remove: (pt) ->
    pt.remove()
  animate: (pt, mark, evtData, tooltip) ->
    renderer[coord.type][mark.type].animate pt, scales, coord, offset, mark, mayflip
    if evtData and _.keys(evtData).length > 0
      pt.data 'e', evtData
    if tooltip
      pt.data 't', tooltip
    pt

class Renderer
  constructor : ->
  render: (paper, scales, coord, offset, mark, mayflip) ->
    pt = @_make(paper)
    for k, v of @attr(scales, coord, offset, mark, mayflip)
      pt.attr(k, v)
    pt
  _make : () -> throw poly.error.impl()
  animate: (pt, scales, coord, offset, mark, mayflip) ->
    pt.animate @attr(scales, coord, offset, mark, mayflip), 300
  attr: (scales, coord, offset, mark, mayflip) -> throw poly.error.impl()
  _makePath : (xs, ys, type='L') ->
    path = _.map xs, (x, i) -> (if i == 0 then 'M' else type) + x+' '+ys[i]
    path.join(' ')
  _maybeApply : (scales, mark, key) ->
    val = mark[key]
    if _.isObject(val) and val.f is 'identity'
      val.v
    else if scales[key]?
      scales[key].f(val)
    else
      val
  _applyOffset: (x, y, offset) ->
    if not offset then return {x: x, y: y}
    offset.x ?= 0
    offset.y ?= 0
    x : if _.isArray(x) then (i+offset.x for i in x) else x+offset.x
    y : if _.isArray(y) then (i+offset.y for i in y) else y+offset.y
  _shared : (scales, mark, attr) ->
    maybeAdd = (aes) =>
      if mark[aes]? and not attr[aes]?
        attr[aes] = @_maybeApply scales, mark, aes
    maybeAdd('opacity')
    maybeAdd('stroke-width')
    maybeAdd('stroke-dasharray')
    maybeAdd('stroke-dashoffset')
    maybeAdd('transform')
    maybeAdd('font-size')
    maybeAdd('font-weight')
    maybeAdd('font-family')
    attr


class Circle extends Renderer # for both cartesian & polar
  _make: (paper) -> paper.circle()
  attr: (scales, coord, offset, mark, mayflip) ->
    {x, y} = coord.getXY mayflip, mark
    {x, y} = @_applyOffset(x, y, offset)
    stroke = @_maybeApply scales, mark,
      if mark.stroke then 'stroke' else 'color'
    attr =
      cx: x
      cy: y
      r: @_maybeApply scales, mark, 'size'
      stroke: stroke

    fill = @_maybeApply scales, mark, 'color'
    if fill and fill isnt 'none' then attr.fill = fill

    @_shared scales, mark, attr

class Path extends Renderer # for both cartesian & polar?
  _make: (paper) -> paper.path()
  attr: (scales, coord, offset, mark, mayflip) ->
    {x, y} = coord.getXY mayflip, mark
    {x, y} = @_applyOffset(x, y, offset)
    stroke = @_maybeApply scales, mark,
      if mark.stroke then 'stroke' else 'color'
    @_shared scales, mark,
      path: @_makePath x, y
      stroke: stroke

class Line extends Renderer # for both cartesian & polar?
  _make: (paper) -> paper.path()
  attr: (scales, coord, offset, mark, mayflip) ->
    [mark.x,mark.y] = poly.sortArrays scales.x.sortfn, [mark.x,mark.y]
    {x, y} = coord.getXY mayflip, mark
    {x, y} = @_applyOffset(x, y, offset)
    stroke = @_maybeApply scales, mark,
      if mark.stroke then 'stroke' else 'color'
    @_shared scales, mark,
      path: @_makePath x, y
      stroke: stroke

# The difference between Line and PolarLine is that Polar Line MAY plot a circle
class PolarLine extends Renderer
  _make: (paper) -> paper.path()
  attr: (scales, coord, offset, mark, mayflip) ->
    {x, y, r, t} = coord.getXY mayflip, mark
    {x, y} = @_applyOffset(x, y, offset)
    path =
      if _.max(r) - _.min(r) < poly.const.epsilon
        r = r[0]
        path = "M #{x[0]} #{y[0]}"
        for i in [1..x.length-1]
          large = if Math.abs(t[i]-t[i-1]) > Math.PI then 1 else 0
          dir = if t[i]-t[i-1] > 0 then 1 else 0
          path += "A #{r} #{r} 0 #{large} #{dir} #{x[i]} #{y[i]}"
        path
      else
        @_makePath x, y
    stroke = @_maybeApply scales, mark,
      if mark.stroke then 'stroke' else 'color'
    @_shared scales, mark,
      path: path
      stroke: stroke

class Area extends Renderer # for both cartesian & polar?
  _make: (paper) -> paper.path()
  attr: (scales, coord, offset, mark, mayflip) ->
    [x, y] = poly.sortArrays scales.x.sortfn, [mark.x,mark.y.top]
    top = coord.getXY mayflip, {x:x, y:y}
    top = @_applyOffset(top.x, top.y, offset)
    [x, y] = poly.sortArrays ((a) -> -scales.x.sortfn(a)), [mark.x,mark.y.bottom]
    bottom = coord.getXY mayflip, {x:x, y:y}
    bottom = @_applyOffset(bottom.x, bottom.y, offset)
    x = top.x.concat bottom.x
    y = top.y.concat bottom.y
    @_shared scales, mark,
      path: @_makePath x, y
      stroke: @_maybeApply scales, mark, 'color'
      fill: @_maybeApply scales, mark, 'color'
      'stroke-width': '0px'

class Rect extends Renderer # for CARTESIAN only
  _make: (paper) -> paper.rect()
  attr: (scales, coord, offset, mark, mayflip) ->
    {x, y} = coord.getXY mayflip, mark
    {x, y} = @_applyOffset(x, y, offset)
    stroke = @_maybeApply scales, mark,
      if mark.stroke then 'stroke' else 'color'
    @_shared scales, mark,
      x: _.min x
      y: _.min y
      width: Math.abs x[1]-x[0]
      height: Math.abs y[1]-y[0]
      fill: @_maybeApply scales, mark, 'color'
      stroke: stroke
      'stroke-width': @_maybeApply scales, mark, 'stroke-width' ? '0px'

class CircleRect extends Renderer # FOR POLAR ONLY
  _make: (paper) -> paper.path()
  attr: (scales, coord, offset, mark, mayflip) ->
    [x0, x1] = mark.x
    [y0, y1] = mark.y
    mark.x = [x0, x0, x1, x1]
    mark.y = [y0, y1, y1, y0]
    {x, y, r, t} = coord.getXY mayflip, mark
    {x, y} = @_applyOffset(x, y, offset)
    if coord.flip
      x.push x.splice(0,1)[0]
      y.push y.splice(0,1)[0]
      r.push r.splice(0,1)[0]
      t.push t.splice(0,1)[0]
    large = if Math.abs(t[1]-t[0]) > Math.PI then 1 else 0
    path = "M #{x[0]} #{y[0]} A #{r[0]} #{r[0]} 0 #{large} 1 #{x[1]} #{y[1]}"
    large = if Math.abs(t[3]-t[2]) > Math.PI then 1 else 0
    path += "L #{x[2]} #{y[2]} A #{r[2]} #{r[2]} 0 #{large} 0 #{x[3]} #{y[3]} Z"

    stroke = @_maybeApply scales, mark,
      if mark.stroke then 'stroke' else 'color'
    @_shared scales, mark,
      path: path
      fill: @_maybeApply scales, mark, 'color'
      stroke: stroke
      'stroke-width': @_maybeApply scales, mark, 'stroke-width' ? '0px'

class Text extends Renderer # for both cartesian & polar
  _make: (paper) -> paper.text()
  attr: (scales, coord, offset, mark, mayflip) ->
    {x, y} = coord.getXY mayflip, mark
    {x, y} = @_applyOffset(x, y, offset)

    @_shared scales, mark,
      x: x
      y: y
      r: 10
      text: @_maybeApply  scales, mark, 'text'
      'text-anchor' : mark['text-anchor'] ? 'left'
      fill: @_maybeApply(scales, mark, 'color') or 'black'

renderer =
  cartesian:
    circle: new Circle()
    line: new Line()
    pline: new Line() # may plot a circle in polar coord, but same as line here
    area: new Area()
    path: new Path()
    text: new Text()
    rect: new Rect()
  polar:
    circle: new Circle()
    path: new Path()
    line: new Line()
    pline: new PolarLine() # pline may plot a circle
    area: new Area()
    text: new Text()
    rect: new CircleRect()
