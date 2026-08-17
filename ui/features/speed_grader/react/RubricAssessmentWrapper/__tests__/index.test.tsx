/*
 * Copyright (C) 2026 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import React from 'react'
import {render, screen} from '@testing-library/react'
import fakeENV from '@canvas/test-utils/fakeENV'
import RubricAssessmentWrapper from '../index'
import useStore from '../../../stores'
import {mergeSavedRubricAssessment} from '../../../jquery/speed_grader.utils'

const rubric = {
  id: '1',
  title: 'Jury rubric',
  criteria: [
    {
      id: '_7077',
      description: 'Technological Novelty',
      long_description: '',
      criterion_use_range: true,
      points: 5,
      ratings: [
        {id: 'r0', criterion_id: '_7077', description: 'Poor', long_description: '', points: 0},
        {id: 'r1', criterion_id: '_7077', description: 'Good', long_description: '', points: 3},
        {
          id: 'r2',
          criterion_id: '_7077',
          description: 'Excellent',
          long_description: '',
          points: 5,
        },
      ],
    },
  ],
  hide_points: false,
  rating_order: 'descending',
  free_form_criterion_comments: false,
  points_possible: 5,
  workflow_state: 'active',
} as any

const assessment = (points: number, updatedAt: string) => ({
  id: '69',
  assessor_id: '121',
  assessment_type: 'grading',
  updated_at: updatedAt,
  score: points,
  data: [{id: 'd1', criterion_id: '_7077', points, comments: '', description: ''}],
})

// what the page payload actually looks like for a grader who cannot see other grader identities:
// assessor_id is stripped and only the anonymous id identifies the author
const anonymousAssessment = (anonymousAssessorId: string) => {
  const {assessor_id: _assessorId, ...rest} = assessment(4.44, '2026-08-06T11:39:18Z')
  return {...rest, anonymous_assessor_id: anonymousAssessorId}
}

const renderWrapper = (currentUserId = '121') =>
  render(
    <RubricAssessmentWrapper
      currentUserId={currentUserId}
      rubric={rubric}
      onDismiss={() => {}}
      onSave={() => {}}
      onReset={() => {}}
    />,
  )

const shownPoints = () =>
  screen.getByTestId('rubric-assessment-slider-display').textContent?.match(/[\d.]+ \/ 5/)?.[0]

describe('RubricAssessmentWrapper', () => {
  beforeEach(() => {
    useStore.setState({rubricSavedComments: {}, selfAssessment: null})
  })

  afterEach(() => {
    fakeENV.teardown()
  })

  it('shows the saved ratings for the selected assessment', () => {
    useStore.setState({studentAssessment: assessment(4.44, '2026-08-06T11:39:18Z') as any})
    renderWrapper()

    expect(shownPoints()).toBe('4.44 / 5')
  })

  it('is read-only when the selected assessment belongs to someone else', () => {
    useStore.setState({studentAssessment: assessment(4.44, '2026-08-06T11:39:18Z') as any})
    renderWrapper('11')

    expect(screen.getByTestId('rubric-slider-input')).toBeDisabled()
  })

  it('stays editable for your own assessment', () => {
    useStore.setState({studentAssessment: assessment(4.44, '2026-08-06T11:39:18Z') as any})
    renderWrapper()

    expect(screen.getByTestId('rubric-slider-input')).toBeEnabled()
  })

  it('stays editable for your own assessment when only the anonymous id identifies you', () => {
    fakeENV.setup({current_anonymous_id: 'Z6xwS'})
    useStore.setState({studentAssessment: anonymousAssessment('Z6xwS') as any})
    renderWrapper('143')

    expect(screen.getByTestId('rubric-slider-input')).toBeEnabled()
    expect(screen.getByTestId('reset-rubric-assessment-button')).toBeInTheDocument()
  })

  it('is read-only for another grader when anonymous ids do not match', () => {
    fakeENV.setup({current_anonymous_id: 'Z6xwS'})
    useStore.setState({studentAssessment: anonymousAssessment('qWeR1') as any})
    renderWrapper('143')

    expect(screen.getByTestId('rubric-slider-input')).toBeDisabled()
  })

  it('stays editable when no assessment is selected yet', () => {
    useStore.setState({studentAssessment: {} as any})
    renderWrapper('11')

    expect(screen.getByTestId('rubric-slider-input')).toBeEnabled()
  })

  it('re-renders with the ratings returned by a save', () => {
    const stored = [assessment(4.44, '2026-08-06T11:39:18Z')] as any[]
    useStore.setState({studentAssessment: stored[0]})
    renderWrapper()
    expect(shownPoints()).toBe('4.44 / 5')

    mergeSavedRubricAssessment(stored, {
      id: 69,
      assessor_id: 121,
      assessment_type: 'grading',
      updated_at: '2026-08-06T11:40:00Z',
      score: 2.22,
      data: [{id: 'd1', criterion_id: '_7077', points: 2.22, comments: '', description: ''}],
    } as any)
    useStore.setState({studentAssessment: stored[0]})

    expect(shownPoints()).toBe('2.22 / 5')
  })
})
