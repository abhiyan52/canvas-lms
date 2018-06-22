#
# Copyright (C) 2013 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

define [
  'i18n!gradezilla'
  'jquery'
  'underscore'
  'react'
  'react-dom'
  'Backbone'
  'vendor/slickgrid'
  '../../gradezilla/OutcomeGradebookGrid'
  '../gradezilla/CheckboxView'
  '../gradebook/SectionMenuView'
  'jsx/gradezilla/default_gradebook/components/SectionFilter'
  'jst/gradezilla/outcome_gradebook'
  'vendor/jquery.ba-tinypubsub'
  '../../jquery.rails_flash_notifications'
  'jquery.instructure_misc_plugins'
], (I18n, $, _, React, ReactDOM, {View}, Slick, Grid, CheckboxView, SectionMenuView, SectionFilter, template, cellTemplate) ->

  Dictionary =
    exceedsMastery:
      color : '#127A1B'
      label : I18n.t('Exceeds Mastery')
    mastery:
      color : if ENV.use_high_contrast then '#127A1B' else '#00AC18'
      label : I18n.t('Meets Mastery')
    nearMastery:
      color : if ENV.use_high_contrast then '#C23C0D' else '#FC5E13'
      label : I18n.t('Near Mastery')
    remedial:
      color : '#EE0612'
      label : I18n.t('Well Below Mastery')

  class OutcomeGradebookView extends View

    tagName: 'div'

    className: 'outcome-gradebook'

    template: template

    @optionProperty 'gradebook'

    hasOutcomes: $.Deferred()

    # child views rendered using the {{view}} helper in the template
    checkboxes: [
      new CheckboxView(Dictionary.exceedsMastery),
      new CheckboxView(Dictionary.mastery),
      new CheckboxView(Dictionary.nearMastery),
      new CheckboxView(Dictionary.remedial)
    ]

    ratings: []

    events:
      'click .sidebar-toggle': 'onSidebarToggle'

    constructor: (options) ->
      super
      @_validateOptions(options)
      if ENV.GRADEBOOK_OPTIONS.outcome_proficiency?.ratings
        @ratings = ENV.GRADEBOOK_OPTIONS.outcome_proficiency.ratings
        @checkboxes = @ratings.map (rating) -> new CheckboxView({color: "\##{rating.color}", label: rating.description})

    # Public: Show/hide the sidebar.
    #
    # e - Event object.
    #
    # Returns nothing.
    onSidebarToggle: (e) ->
      e.preventDefault()
      isCollapsed = @_toggleSidebarCollapse()
      @_toggleSidebarArrow()
      @_toggleSidebarTooltips(isCollapsed)

    # Internal: Toggle collapsed class on sidebar.
    #
    # Returns true if collapsed, false if expanded.
    _toggleSidebarCollapse: ->
      @$('.outcome-gradebook-sidebar')
        .toggleClass('collapsed')
        .hasClass('collapsed')

    # Internal: Toggle the direction of the sidebar collapse arrow.
    #
    # Returns nothing.
    _toggleSidebarArrow: ->
      @$('.sidebar-toggle')
        .toggleClass('icon-arrow-open-right')
        .toggleClass('icon-arrow-open-left')

    # Internal: Toggle the direction of the sidebar collapse arrow.
    #
    # Returns nothing.
    _toggleSidebarTooltips: (shouldShow) ->
      if shouldShow
        @$('.checkbox-view').each ->
          $(this).find('.checkbox')
            .attr('data-tooltip', 'left')
            .attr('title', $(this).find('.checkbox-label').text())
      else
        @$('.checkbox').removeAttr('data-tooltip').removeAttr('title')

    # Internal: Validate options passed to constructor.
    #
    # options - The options hash passed to the constructor function.
    #
    # Returns nothing on success, raises on failure.
    _validateOptions: ({gradebook}) ->
      throw new Error('Missing required option: "gradebook"') unless gradebook

    # Internal: Listen for events on child views.
    #
    # Returns nothing.
    _attachEvents: ->
      view.on('togglestate', @_createFilter("rating_#{i}")) for view, i in @checkboxes
      $.subscribe('currentSection/change', Grid.Events.sectionChangeFunction(@grid))
      $.subscribe('currentSection/change', @updateExportLink)
      @updateExportLink(@gradebook.getFilterRowsBySetting('sectionId'))

    # Internal: Listen for events on grid.
    #
    # Returns nothing.
    _attachGridEvents: ->
      @grid.onHeaderRowCellRendered.subscribe(Grid.Events.headerRowCellRendered)
      @grid.onHeaderCellRendered.subscribe(Grid.Events.headerCellRendered)
      @grid.onSort.subscribe(Grid.Events.sort)

    # Public: Create object to be passed to the view.
    #
    # Returns an object.
    toJSON: ->
      _.extend({}, checkboxes: @checkboxes)

    # Public: Render the view once all needed data is loaded.
    #
    # Returns this.
    render: ->
      $.when(@gradebook.hasSections)
        .then(=> super)
        .then(@renderSectionMenu)
      $.when(@hasOutcomes).then(@renderGrid)
      this

    # Internal: Render SlickGrid component.
    #
    # response - Outcomes rollup data from API.
    #
    # Returns nothing.
    renderGrid: (response) =>
      Grid.filter = _.range(@checkboxes.length).map (i) -> "rating_#{i}"
      Grid.ratings = @ratings
      Grid.Util.saveOutcomes(response.linked.outcomes)
      Grid.Util.saveStudents(response.linked.users)
      Grid.Util.saveOutcomePaths(response.linked.outcome_paths)
      Grid.Util.saveSections(@gradebook.sections) # might want to put these into the api results at some point
      [columns, rows] = Grid.Util.toGrid(response, column: { formatter: Grid.View.cell }, row: { section: @gradebook.getFilterRowsBySetting('sectionId') })
      @grid = new Slick.Grid(
        '.outcome-gradebook-wrapper',
        rows,
        columns,
        Grid.options)
      @_attachGridEvents()
      @grid.init()
      Grid.Events.init(@grid)
      @_attachEvents()

    isLoaded: false
    onShow: ->
      @loadOutcomes() if !@isLoaded
      @isLoaded = true
      @$el.fillWindowWithMe({
        onResize: => @grid.resizeCanvas() if @grid
      })
      $(".post-grades-button-placeholder").hide();

    # Internal: Render Section selector.
    # Returns nothing.
    renderSectionMenu: =>
      sectionList = @gradebook.sectionList()
      mountPoint = document.querySelector('[data-component="SectionFilter"]')
      if sectionList.length > 1
        selectedSectionId = @gradebook.getFilterRowsBySetting('sectionId') || '0'
        props =
          items: sectionList
          onSelect: @updateCurrentSection
          selectedItemId: selectedSectionId
          disabled: false

        component = React.createElement(SectionFilter, props)
        @sectionFilterMenu = ReactDOM.render(component, mountPoint)

    updateCurrentSection: (sectionId) =>
      @gradebook.updateCurrentSection(sectionId)
      Grid.Events.sectionChangeFunction(@grid)(sectionId)
      @updateExportLink(sectionId)
      @renderSectionMenu()

    # Public: Load all outcome results from API.
    #
    # Returns nothing.
    loadOutcomes: () ->
      $.when(@gradebook.hasSections).then(@_loadOutcomes)

    _loadOutcomes: =>
      course = ENV.context_asset_string.split('_')[1]
      @$('.outcome-gradebook-wrapper').disableWhileLoading(@hasOutcomes)
      @_loadPage("/api/v1/courses/#{course}/outcome_rollups?per_page=100&include[]=outcomes&include[]=users&include[]=outcome_paths")

    # Internal: Load a page of outcome results from the given URL.
    #
    # url - The URL to load results from.
    # outcomes - An existing response from the API.
    #
    # Returns nothing.
    _loadPage: (url, outcomes) ->
      dfd  = $.getJSON(url).fail((e) ->
        $.flashError(I18n.t('There was an error fetching outcome results'))
      )
      dfd.then (response, status, xhr) =>
        outcomes = @_mergeResponses(outcomes, response)
        if response.meta.pagination.next
          @_loadPage(response.meta.pagination.next, outcomes)
        else
          @hasOutcomes.resolve(outcomes)

    # Internal: Merge two API responses into one.
    #
    # a - The first API response received.
    # b - The second API response received.
    #
    # Returns nothing.
    _mergeResponses: (a, b) ->
      return b unless a
      response = {}
      response.meta    = _.extend({}, a.meta, b.meta)
      response.linked  = {
        outcomes: a.linked.outcomes
        outcome_paths: a.linked.outcome_paths
        users: a.linked.users.concat(b.linked.users)
      }
      response.rollups = a.rollups.concat(b.rollups)
      response

    # Internal: Create an event listener function used to filter SlickGrid results.
    #
    # name - The class name to toggle on/off (e.g. 'mastery', 'remedial').
    #
    # Returns a function.
    _createFilter: (name) ->
      filterFunction = (isChecked) =>
        Grid.filter = if isChecked
          _.uniq(Grid.filter.concat([name]))
        else
          _.reject(Grid.filter, (o) -> o == name)
        @grid.invalidate()

    updateExportLink: (section) =>
      url = "#{ENV.GRADEBOOK_OPTIONS.context_url}/outcome_rollups.csv"
      url += "?section_id=#{section}" if section and section != '0'
      $('.export-content').attr('href', url)
