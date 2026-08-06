/*
 * Copyright (C) 2024 - present Instructure, Inc.
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

import React, {useMemo, useCallback} from 'react'
import useStore from '../../stores'
import type {RubricAssessmentData} from '@canvas/rubrics/react/types/rubric'
import {
  mapRubricAssessmentDataUnderscoredKeysToCamelCase,
  mapRubricUnderscoredKeysToCamelCase,
  type RubricOutcomeUnderscore,
  type RubricUnderscoreType,
} from '@canvas/rubrics/react/utils'
import {View} from '@instructure/ui-view'
import {Button} from '@instructure/ui-buttons'
import {useScope as createI18nScope} from '@canvas/i18n'
import {windowConfirm} from '@canvas/util/globalUtils'
import {RubricAssessmentContainerWrapper} from '@canvas/rubrics/react/RubricAssessment'

const I18n = createI18nScope('speed_grader')

const convertSubmittedAssessment = (assessments: RubricAssessmentData[]): any => {
  const {assessment_user_id, anonymous_id, assessment_type} = ENV.RUBRIC_ASSESSMENT ?? {}

  const data: {[key: string]: string | undefined | number} = {}
  if (assessment_user_id) {
    data['rubric_assessment[user_id]'] = assessment_user_id
  } else {
    data['rubric_assessment[anonymous_id]'] = anonymous_id
  }

  data['rubric_assessment[assessment_type]'] = assessment_type

  assessments.forEach(assessment => {
    const pre = `rubric_assessment[criterion_${assessment.criterionId}]`
    data[pre + '[points]'] = assessment.points
    data[pre + '[comments]'] = assessment.comments
    data[pre + '[save_comment]'] = assessment.saveCommentsForLater ? '1' : '0'
    data[pre + '[description]'] = assessment.description
    if (assessment.id) {
      data[pre + '[rating_id]'] = assessment.id
    }
  })

  return data
}

type RubricAssessmentWrapperProps = {
  currentUserId: string
  rubric: RubricUnderscoreType
  rubricOutcomeData?: RubricOutcomeUnderscore[]
  onDismiss: () => void
  onSave: (assessmentData: any) => void
  onReset?: (assessmentId: string) => void
}
export default ({
  currentUserId,
  rubric,
  rubricOutcomeData,
  onDismiss,
  onSave,
  onReset,
}: RubricAssessmentWrapperProps) => {
  const {
    currentStudentAvatarPath,
    currentStudentName,
    rubricHidePoints,
    rubricSavedComments = {},
    selfAssessment,
    studentAssessment,
  } = useStore()

  const handleSubmit = useCallback(
    (assessmentData: RubricAssessmentData[]) => {
      const data = convertSubmittedAssessment(assessmentData)
      onSave(data)
    },
    [onSave],
  )

  const mappedRubric = useMemo(
    () => mapRubricUnderscoredKeysToCamelCase(rubric, rubricOutcomeData),
    [rubric, rubricOutcomeData],
  )

  const rubricAssessmentData = useMemo(() => {
    if (studentAssessment?.assessment_type === 'peer_review') return []
    return mapRubricAssessmentDataUnderscoredKeysToCamelCase(studentAssessment?.data ?? [])
  }, [studentAssessment])

  const mappedSelfAssessment = useMemo(
    () =>
      selfAssessment && selfAssessment.data
        ? mapRubricAssessmentDataUnderscoredKeysToCamelCase(selfAssessment.data)
        : undefined,
    [selfAssessment],
  )

  const submissionUser = useMemo(
    () => ({name: currentStudentName, avatarUrl: currentStudentAvatarPath}),
    [currentStudentName, currentStudentAvatarPath],
  )

  const ownSavedAssessmentId =
    studentAssessment?.id && String(studentAssessment.assessor_id ?? '') === String(currentUserId)
      ? String(studentAssessment.id)
      : undefined

  return (
    <View as="div">
      {onReset && ownSavedAssessmentId && (
        <View as="div" textAlign="end" margin="0 0 x-small 0">
          <Button
            size="small"
            data-testid="reset-rubric-assessment-button"
            onClick={() => {
              if (
                windowConfirm(
                  I18n.t(
                    'Remove your saved assessment for this student? This clears your ratings and score for them.',
                  ),
                )
              ) {
                onReset(ownSavedAssessmentId)
              }
            }}
          >
            {I18n.t('Reset my assessment')}
          </Button>
        </View>
      )}
      <RubricAssessmentContainerWrapper
        key={`${studentAssessment?.id ?? 'new'}-${studentAssessment?.updated_at ?? ''}`}
        buttonDisplay={mappedRubric?.buttonDisplay ?? 'level'}
        criteria={mappedRubric?.criteria ?? []}
        currentUserId={currentUserId}
        hidePoints={true}
        isPreviewMode={false}
        isPeerReview={false}
        isFreeFormCriterionComments={mappedRubric?.freeFormCriterionComments ?? false}
        isStandaloneContainer={true}
        ratingOrder={mappedRubric?.ratingOrder ?? 'descending'}
        rubricTitle={rubric.title}
        rubricAssessmentData={rubricAssessmentData}
        rubricSavedComments={rubricSavedComments}
        selfAssessment={mappedSelfAssessment}
        selfAssessmentDate={selfAssessment?.updated_at}
        submissionUser={submissionUser}
        onDismiss={onDismiss}
        onSubmit={handleSubmit}
        viewModeOverride="traditional"
      />
    </View>
  )
}
