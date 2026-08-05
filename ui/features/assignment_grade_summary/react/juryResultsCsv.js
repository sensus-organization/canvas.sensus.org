const BOM = '\uFEFF'
const SPREADSHEET_FORMULA = /^[=+\-@\t\r]/

function field(value) {
  const text = String(value ?? '')
  const safe = typeof value !== 'number' && SPREADSHEET_FORMULA.test(text) ? `'${text}` : text
  return `"${safe.replace(/"/g, '""')}"`
}

export function buildRatingsCsv({ratings, names = {}, criterionNames = {}, headers}) {
  const rows = ratings.flatMap(([teamId, teamRatings]) =>
    teamRatings.map(rating => [
      names[teamId] || teamId,
      names[rating.juror] || rating.juror,
      criterionNames[rating.criterion] || rating.criterion,
      rating.score,
      rating.criterion_points,
      rating.normalized_score,
      rating.comments,
    ]),
  )

  return BOM + [headers, ...rows].map(row => row.map(field).join(',')).join('\r\n')
}
