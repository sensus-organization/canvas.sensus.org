import React, {Component} from 'react'
import {bool, shape, string} from 'prop-types'
import {Button} from '@instructure/ui-buttons'
import {Alert} from '@instructure/ui-alerts'
import {Heading} from '@instructure/ui-heading'
import {Spinner} from '@instructure/ui-spinner'
import axios from '@canvas/axios'
import {useScope as createI18nScope} from '@canvas/i18n'
import {windowConfirm} from '@canvas/util/globalUtils'
import {buildRatingsCsv} from '../juryResultsCsv'

const I18n = createI18nScope('assignment_grade_summary')

function path(assignment) {
  return `/api/v1/courses/${assignment.courseId}/assignments/${assignment.id}/jury_results`
}

export default class JuryResults extends Component {
  static propTypes = {
    assignment: shape({
      courseId: string.isRequired,
      gradesPublished: bool.isRequired,
      id: string.isRequired,
      title: string.isRequired,
    }).isRequired,
  }

  state = {loading: true, progress: null, published: false, run: null, readiness: null, error: null}

  progressTimer = null

  componentDidMount() {
    this.load()
  }

  componentWillUnmount() {
    this.stopProgressPolling()
  }

  load = async () => {
    try {
      const {data} = await axios.get(path(this.props.assignment))
      const run = data.jury_grading_run || data
      this.setState({loading: false, progress: run.progress || null, run: run.id ? run : null, readiness: data.readiness || null, error: null}, this.pollProgress)
    } catch (_) {
      this.setState({loading: false, error: I18n.t('Could not load Jury results.')})
    }
  }

  calculate = async () => {
    this.setState({loading: true, error: null})
    try {
      const {data} = await axios.post(path(this.props.assignment))
      const run = data.jury_grading_run || data
      this.setState({loading: false, progress: run.progress || null, run, readiness: data.readiness || this.state.readiness}, this.pollProgress)
    } catch (error) {
      this.setState({loading: false, error: error.response?.data?.message || I18n.t('Could not calculate Jury results.')})
    }
  }

  publish = async () => {
    if (!windowConfirm(I18n.t('Publish the adjusted Jury results? This cannot be undone.'))) return
    try {
      await axios.post(`${path(this.props.assignment)}/publish`, {run_id: this.state.run.id})
      this.setState({published: true}, this.load)
    } catch (error) {
      this.setState({error: error.response?.data?.message || I18n.t('Could not publish Jury results.')})
    }
  }

  downloadRatings = (ratings, names, criterionNames) => {
    const csv = buildRatingsCsv({
      ratings,
      names,
      criterionNames,
      headers: [
        I18n.t('Team'),
        I18n.t('Jury'),
        I18n.t('Criterion'),
        I18n.t('Score'),
        I18n.t('Criterion points'),
        I18n.t('Normalized (/5)'),
        I18n.t('Comment'),
      ],
    })
    const url = URL.createObjectURL(new Blob([csv], {type: 'text/csv;charset=utf-8'}))
    const link = document.createElement('a')
    link.href = url
    link.download = `jury-ratings-${this.props.assignment.id}.csv`
    link.click()
    URL.revokeObjectURL(url)
  }

  stopProgressPolling = () => {
    if (this.progressTimer) clearInterval(this.progressTimer)
    this.progressTimer = null
  }

  pollProgress = () => {
    const {run} = this.state
    const progressId = run?.progress?.id
    const running = run?.workflow_state === 'queued' || run?.workflow_state === 'running'
    if (!progressId || !running) {
      this.stopProgressPolling()
      return
    }
    if (this.progressTimer) return

    const poll = async () => {
      try {
        const {data} = await axios.get(`/api/v1/progress/${progressId}`)
        this.setState({progress: data})
        if (data.workflow_state === 'completed' || data.workflow_state === 'failed') {
          this.stopProgressPolling()
          this.load()
        }
      } catch (_) {
        // Keep the calculation page usable even if one status poll fails.
      }
    }
    poll()
    this.progressTimer = setInterval(poll, 1000)
  }

  render() {
    const {assignment} = this.props
    const {error, loading, progress, published, run, readiness} = this.state
    const results = run?.results || {}
    const teams = Object.entries(results.teams || {})
    const jurors = Object.entries(results.jurors || {})
    const criteria = Object.entries(results.model?.criterion_effects || {})
    const ratings = Object.entries(results.ratings || {})
    const coverage = readiness?.coverage
    const allocation = coverage?.distribution?.allocated
    const completed = coverage?.distribution?.completed
    const names = {...(readiness?.user_names || {}), ...(run?.user_names || {})}
    const criterionNames = {...(readiness?.criterion_names || {}), ...(run?.criterion_names || {})}
    const missing = coverage?.missing || []
    const issues = readiness?.issues || []
    const observations = readiness?.observations || []
    const criterionIds = coverage?.criterion_ids || []
    const allocations = readiness?.allocations || []
    const nameOf = id => names[id] || id
    const byName = (a, b) => String(nameOf(a)).localeCompare(String(nameOf(b)))

    // observations carry what the Jury has actually entered, and arrive on every load, so the
    // ratings and the coverage grid stay readable long before a calculation is possible
    const observedBy = new Map()
    observations.forEach(row => {
      const key = `${row.juror}-${row.team}`
      if (!observedBy.has(key)) observedBy.set(key, [])
      observedBy.get(key).push(row)
    })
    const observedRatings = observations.reduce((acc, row) => {
      const team = String(row.team)
      acc[team] = acc[team] || []
      acc[team].push({
        ...row,
        normalized_score: row.criterion_points ? (row.score / row.criterion_points) * 5 : undefined,
      })
      return acc
    }, {})
    const ratingsSource = ratings.length > 0 ? ratings : Object.entries(observedRatings)
    const matrixJurors = [...new Set(allocations.map(([jurorId]) => jurorId))].sort(byName)
    const matrixTeams = [...new Set(allocations.map(([, teamId]) => teamId))].sort(byName)
    const allocated = new Set(allocations.map(([jurorId, teamId]) => `${jurorId}-${teamId}`))
    const jurorsWithRatings = [...new Set(observations.map(row => row.juror))].sort(byName)
    const rankColumns = [
      teams.length > 1 && ['top_1_probability', I18n.t('Top 1')],
      teams.length > 3 && ['top_3_probability', I18n.t('Top 3')],
      teams.length > 5 && ['top_5_probability', I18n.t('Top 5')],
    ].filter(Boolean)
    const running = run?.workflow_state === 'queued' || run?.workflow_state === 'running'
    const canCalculate = !issues.length
    const gradesPublished = assignment.gradesPublished || published
    const canPublish = run?.workflow_state === 'completed' && !issues.length && !(results.blocking_warnings || []).length && !readiness?.stale && !(coverage?.ungraded_team_ids || []).length && !gradesPublished
    const progressId = run?.progress?.id
    const progressCompletion = Math.round(progress?.completion || run?.progress?.completion || 0)
    const scoreScale = results.model?.score_scale || teams[0]?.[1]?.score_scale

    return (
      <div>
        <Heading level="h1">{I18n.t('Jury results')}</Heading>
        <p>{assignment.title}</p>
        {error && <Alert variant="error" margin="medium 0">{error}</Alert>}
        {issues.map(issue => <Alert key={issue} variant="error" margin="medium 0">{issue}</Alert>)}
        {readiness?.stale && <Alert variant="error" margin="medium 0">{I18n.t('Jury ratings changed after this result was calculated. Recalculate before publishing.')}</Alert>}
        {run?.workflow_state === 'failed' && <Alert variant="error" margin="medium 0">{run.progress?.message || results.error || I18n.t('Jury calculation failed. Calculate again.')}</Alert>}
        {(results.warnings || []).map(warning => <Alert key={warning} variant="warning" margin="medium 0">{warning}</Alert>)}
        {coverage && (
          <>
            <Heading level="h2" margin="large 0 small">{I18n.t('Grading coverage')}</Heading>
            <p>
              {I18n.t('%{assessmentsComplete}/%{assessmentsAllocated} assigned assessments complete · %{ratingsComplete}/%{ratingsAllocated} rubric ratings complete', {
                assessmentsComplete: coverage.completed_assessments,
                assessmentsAllocated: coverage.allocated_assessments,
                ratingsComplete: coverage.completed_ratings,
                ratingsAllocated: coverage.allocated_ratings,
              })}
            </p>
            {allocation && completed && (
              <p>
                {I18n.t('Allocation: %{teams}/%{teamCount} teams have 2+ Jury members; Jurors/team %{minimum}/%{median}/%{maximum} (min/median/max); %{sharedPairs}/%{possiblePairs} Jury pairs share a team; %{connected}.', {
                  teams: allocation.teams_with_multiple_jurors,
                  teamCount: coverage.team_count,
                  minimum: allocation.team_jury_count_min,
                  median: allocation.team_jury_count_median,
                  maximum: allocation.team_jury_count_max,
                  sharedPairs: allocation.shared_jury_pairs,
                  possiblePairs: allocation.possible_jury_pairs,
                  connected: allocation.connected ? I18n.t('connected') : I18n.t('disconnected'),
                })}<br />
                {I18n.t('Entered ratings: %{teams}/%{teamCount} teams have 2+ Jury members; Jurors/team %{minimum}/%{median}/%{maximum} (min/median/max); %{sharedPairs}/%{possiblePairs} Jury pairs linked; %{connected}.', {
                  teams: completed.teams_with_multiple_jurors,
                  teamCount: coverage.team_count,
                  minimum: completed.team_jury_count_min,
                  median: completed.team_jury_count_median,
                  maximum: completed.team_jury_count_max,
                  sharedPairs: completed.shared_jury_pairs,
                  possiblePairs: completed.possible_jury_pairs,
                  connected: completed.connected ? I18n.t('connected') : I18n.t('disconnected'),
                })}
              </p>
            )}
            {missing.length > 0 && <Alert variant="error" margin="medium 0">{I18n.t('Missing Jury ratings are included as missing data; calculate is still available. Review the assignments below before publishing.')}</Alert>}
            {coverage.ungraded_team_ids?.length > 0 && <Alert variant="error" margin="medium 0">{I18n.t('Teams with no Jury rating cannot be published: %{teams}.', {teams: coverage.ungraded_team_ids.map(id => names[id] || id).join(', ')})}</Alert>}
            {matrixJurors.length > 0 && (
              <div style={{overflowX: 'auto', marginTop: '1rem'}}>
                <table className="ic-Table ic-Table--hover-row">
                  <caption style={{captionSide: 'top', textAlign: 'left', paddingBottom: '0.5rem'}}>
                    {I18n.t('Rubric criteria entered per Jury member and team, out of %{total}. A dash means the team is not allocated to that Jury member.', {total: criterionIds.length})}
                  </caption>
                  <thead>
                    <tr>
                      <th>{I18n.t('Jury')}</th>
                      {matrixTeams.map(teamId => <th key={teamId} style={{writingMode: 'vertical-rl', transform: 'rotate(180deg)', whiteSpace: 'nowrap'}}>{nameOf(teamId)}</th>)}
                    </tr>
                  </thead>
                  <tbody>
                    {matrixJurors.map(jurorId => (
                      <tr key={jurorId}>
                        <td style={{whiteSpace: 'nowrap'}}>{nameOf(jurorId)}</td>
                        {matrixTeams.map(teamId => {
                          const key = `${jurorId}-${teamId}`
                          if (!allocated.has(key)) return <td key={teamId} style={{textAlign: 'center'}}>—</td>
                          const done = new Set((observedBy.get(key) || []).map(row => row.criterion)).size
                          return <td key={teamId} style={{textAlign: 'center'}} title={`${nameOf(jurorId)} · ${nameOf(teamId)}`}>{done === criterionIds.length ? '✓' : `${done}/${criterionIds.length}`}</td>
                        })}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </>
        )}
        {jurorsWithRatings.length > 0 && (
          <>
            <Heading level="h2" margin="large 0 small">{I18n.t('Jury ratings entered')}</Heading>
            {jurorsWithRatings.map(jurorId => {
              const jurorRows = observations.filter(row => row.juror === jurorId)
              const teamIds = [...new Set(jurorRows.map(row => row.team))].sort(byName)
              return (
                <details key={jurorId} style={{marginTop: '0.5rem'}}>
                  <summary>{I18n.t('%{juror} — %{teams} teams rated', {juror: nameOf(jurorId), teams: teamIds.length})}</summary>
                  <div style={{overflowX: 'auto'}}>
                    <table className="ic-Table ic-Table--hover-row">
                      <thead><tr><th>{I18n.t('Team')}</th>{criterionIds.map(id => <th key={id}>{criterionNames[id] || id}</th>)}</tr></thead>
                      <tbody>
                        {teamIds.map(teamId => {
                          const teamRows = jurorRows.filter(row => row.team === teamId)
                          const byCriterion = Object.fromEntries(teamRows.map(row => [String(row.criterion), row]))
                          const comments = teamRows.filter(row => row.comments)
                          return (
                            <React.Fragment key={teamId}>
                              <tr>
                                <td style={{whiteSpace: 'nowrap'}}>{nameOf(teamId)}</td>
                                {criterionIds.map(id => {
                                  const row = byCriterion[String(id)]
                                  return <td key={id}>{row ? `${row.score?.toFixed(2)}/${row.criterion_points?.toFixed(2)}` : '—'}</td>
                                })}
                              </tr>
                              {comments.length > 0 && (
                                <tr>
                                  <td colSpan={criterionIds.length + 1} style={{whiteSpace: 'pre-wrap', paddingLeft: '2rem'}}>
                                    {comments.map(row => `${criterionNames[row.criterion] || row.criterion}: ${row.comments}`).join('\n')}
                                  </td>
                                </tr>
                              )}
                            </React.Fragment>
                          )
                        })}
                      </tbody>
                    </table>
                  </div>
                </details>
              )
            })}
          </>
        )}
        <details style={{marginTop: '1rem'}}>
          <summary>{I18n.t('How to read this')}</summary>
          <p>{I18n.t('Every rubric criterion is normalized to a 0–5 scale before calibration. Adjusted grade is then mapped back to the rubric total. Calibration change is adjusted normalized score minus raw normalized average. Rank stability is the share of bootstrap resamples at that rank cutoff, not a probability that a team deserves its grade.')}</p>
          <p>{I18n.t('Scale 1.00 is neutral; higher means a wider scoring range. Positive bias means higher scores. Typical disagreement is the Jury member’s mean absolute residual; lower is closer to the calibrated model.')}</p>
        </details>
        <Button onClick={this.calculate} disabled={loading || running || !canCalculate || gradesPublished}>{I18n.t('Calculate jury results')}</Button>{' '}
        <Button color="primary" onClick={this.publish} disabled={!canPublish}>
          {I18n.t('Publish adjusted grades')}
        </Button>
        {loading && !run && <Spinner renderTitle={I18n.t('Loading Jury results')} margin="medium" />}
        {running && (
          <div data-testid="jury-calculation-progress">
            <p>{I18n.t('Calculating calibrated Jury results…')}</p>
            {progressId ? <><progress aria-label={I18n.t('Calculation progress')} max="100" value={progressCompletion}>{progressCompletion}%</progress> {progressCompletion}%</> : <Spinner renderTitle={I18n.t('Calculating Jury results')} margin="medium" />}
          </div>
        )}
        {teams.length > 0 && (
          <table className="ic-Table ic-Table--hover-row" style={{marginTop: '1.5rem'}}>
            <thead><tr><th>{I18n.t('Team')}</th><th>{I18n.t('Ratings')}</th><th>{I18n.t('Raw average (/5)')}</th><th>{I18n.t('Jury disagreement (normalized SD)')}</th><th>{I18n.t('Adjusted grade (out of %{points})', {points: scoreScale})}</th><th>{I18n.t('Calibration change (/5)')}</th><th>{I18n.t('Rank')}</th>{rankColumns.map(([, label]) => <th key={label}>{I18n.t('Rank stability: %{label}', {label})}</th>)}</tr></thead>
            <tbody>{teams.map(([teamId, result]) => (
              <tr key={teamId}><td>{names[teamId] || teamId}</td><td>{result.observation_count}</td><td>{result.raw_average?.toFixed(2)}</td><td>{result.score_standard_deviation?.toFixed(2)}</td><td>{result.adjusted_score?.toFixed(2)}</td><td>{result.adjusted_normalized_score === undefined ? '—' : (result.adjusted_normalized_score - result.raw_average).toFixed(2)}</td><td>{result.adjusted_rank}</td>{rankColumns.map(([key]) => <td key={key}>{(result[key] * 100).toFixed(1)}%</td>)}</tr>
            ))}</tbody>
          </table>
        )}
        {jurors.length > 0 && (
          <>
            <Heading level="h2" margin="large 0 small">{I18n.t('Jury calibration')}</Heading>
            <table className="ic-Table ic-Table--hover-row">
              <thead><tr><th>{I18n.t('Jury')}</th><th>{I18n.t('Ratings')}</th><th>{I18n.t('Shared teams')}</th><th>{I18n.t('Scale')}</th><th>{I18n.t('Score bias')}</th><th>{I18n.t('Typical disagreement (MAE)')}</th></tr></thead>
              <tbody>{jurors.map(([jurorId, result]) => (
                <tr key={jurorId}><td>{names[jurorId] || jurorId}</td><td>{result.observation_count}</td><td>{result.shared_team_count}</td><td>{result.effective_slope?.toFixed(2)}</td><td>{result.score_bias?.toFixed(2)}</td><td>{result.mean_absolute_residual?.toFixed(2)}</td></tr>
              ))}</tbody>
            </table>
          </>
        )}
        {ratingsSource.length > 0 && (
          <details style={{marginTop: '1.5rem'}}>
            <summary>{I18n.t('Individual Jury ratings')}</summary>
            <Button margin="small 0 0" onClick={() => this.downloadRatings(ratingsSource, names, criterionNames)}>{I18n.t('Download ratings CSV')}</Button>
            <table className="ic-Table ic-Table--hover-row" style={{marginTop: '1rem'}}>
              <thead><tr><th>{I18n.t('Team')}</th><th>{I18n.t('Jury')}</th><th>{I18n.t('Criterion')}</th><th>{I18n.t('Score')}</th><th>{I18n.t('Normalized (/5)')}</th><th>{I18n.t('Comment')}</th></tr></thead>
              <tbody>{ratingsSource.flatMap(([teamId, teamRatings]) => teamRatings.map((rating, index) => <tr key={`${teamId}-${rating.juror}-${rating.criterion}-${index}`}><td>{names[teamId] || teamId}</td><td>{names[rating.juror] || rating.juror}</td><td>{criterionNames[rating.criterion] || rating.criterion}</td><td>{rating.criterion_points ? `${rating.score?.toFixed(2)}/${rating.criterion_points.toFixed(2)}` : rating.score?.toFixed(2)}</td><td>{rating.normalized_score?.toFixed(2)}</td><td style={{whiteSpace: 'pre-wrap'}}>{rating.comments}</td></tr>))}</tbody>
            </table>
          </details>
        )}
        {(criteria.length > 0 || teams.length > 0 || jurors.length > 0) && (
          <>
            <details style={{marginTop: '1.5rem'}}>
              <summary>{I18n.t('Technical diagnostics')}</summary>
              <p>{I18n.t('Overall mean: %{mean} · Bootstrap samples: %{samples}', {mean: results.model?.overall_mean?.toFixed(2), samples: run?.settings?.bootstrap})}</p>
              {criteria.length > 0 && <table className="ic-Table ic-Table--hover-row"><thead><tr><th>{I18n.t('Criterion')}</th><th>{I18n.t('Effect')}</th></tr></thead><tbody>{criteria.map(([criterionId, effect]) => <tr key={criterionId}><td>{criterionNames[criterionId] || criterionId}</td><td>{effect.toFixed(2)}</td></tr>)}</tbody></table>}
              {teams.length > 0 && <table className="ic-Table ic-Table--hover-row" style={{marginTop: '1rem'}}><thead><tr><th>{I18n.t('Team')}</th><th>{I18n.t('Model effect')}</th></tr></thead><tbody>{teams.map(([teamId, result]) => <tr key={teamId}><td>{names[teamId] || teamId}</td><td>{result.model_effect?.toFixed(2)}</td></tr>)}</tbody></table>}
              {jurors.length > 0 && <table className="ic-Table ic-Table--hover-row" style={{marginTop: '1rem'}}><thead><tr><th>{I18n.t('Jury')}</th><th>{I18n.t('Raw average (/5)')}</th><th>{I18n.t('Agreement RMSE')}</th></tr></thead><tbody>{jurors.map(([jurorId, result]) => <tr key={jurorId}><td>{names[jurorId] || jurorId}</td><td>{result.raw_average?.toFixed(2)}</td><td>{result.residual_rmse?.toFixed(2)}</td></tr>)}</tbody></table>}
            </details>
          </>
        )}
      </div>
    )
  }
}
