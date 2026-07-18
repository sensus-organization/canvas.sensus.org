/*
 * Copyright (C) 2018 - present Instructure, Inc.
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

import {arrayOf, bool, func, number, shape, string} from 'prop-types'
import React from 'react'
import {useScope as createI18nScope} from '@canvas/i18n'
import FinalGraderSelectMenu from './FinalGraderSelectMenu'
import GraderCommentVisibilityCheckbox from './GraderCommentVisibilityCheckbox'
import GraderCountNumberInput from './GraderCountNumberInput'
import GraderNamesVisibleToFinalGraderCheckbox from './GraderNamesVisibleToFinalGraderCheckbox'
import ModeratedGradingCheckbox from './ModeratedGradingCheckbox'
import {direction} from '@canvas/i18n/rtlHelper'

const I18n = createI18nScope('ModeratedGradingFormFieldGroup')

export default class ModeratedGradingFormFieldGroup extends React.Component {
  static propTypes = {
    availableModerators: arrayOf(shape({name: string.isRequired, id: string.isRequired}))
      .isRequired,
    currentGraderCount: number,
    finalGraderID: string,
    graderCommentsVisibleToGraders: bool.isRequired,
    graderNamesVisibleToFinalGrader: bool.isRequired,
    gradedSubmissionsExist: bool.isRequired,
    isGroupAssignment: bool.isRequired,
    isPeerReviewAssignment: bool.isRequired,
    locale: string.isRequired,
    availableGradersCount: number.isRequired,
    juryCalibratedGradingEnabled: bool.isRequired,
    moderatedGradingEnabled: bool.isRequired,
    onGraderCommentsVisibleToGradersChange: func.isRequired,
    onModeratedGradingChange: func.isRequired,
    hideNumberInputErrors: func,
    hideFinalGraderErrors: func,
  }

  static defaultProps = {
    currentGraderCount: null,
    finalGraderID: null,
    juryCalibratedGradingEnabled: false,
  }

  constructor(props) {
    super(props)
    this.state = {
      moderatedGradingChecked: props.moderatedGradingEnabled,
      juryCalibratedGradingChecked: props.juryCalibratedGradingEnabled,
    }
  }

  componentDidUpdate(_, prevState) {
    if (this.state.moderatedGradingChecked !== prevState.moderatedGradingChecked) {
      this.props.onModeratedGradingChange(this.state.moderatedGradingChecked)
    }
  }

  handleModeratedGradingChange = moderatedGradingChecked => {
    this.setState({moderatedGradingChecked})
  }

  handleJuryCalibratedGradingChange = () => {
    this.setState(previous => ({
      juryCalibratedGradingChecked: !previous.juryCalibratedGradingChecked,
      moderatedGradingChecked: !previous.juryCalibratedGradingChecked || previous.moderatedGradingChecked,
    }))
  }

  render() {
    const juryGradingDisabledReason = this.props.gradedSubmissionsExist
      ? I18n.t('Jury-calibrated grading cannot be changed after submissions are graded')
      : this.props.isGroupAssignment
        ? I18n.t('Jury-calibrated grading uses one student to represent each team and cannot be enabled for group assignments')
        : this.props.isPeerReviewAssignment
          ? I18n.t('Jury-calibrated grading cannot be enabled for peer reviewed assignments')
          : null

    return (
      <fieldset>
        <div className={`form-column-${direction('left')}`}>{I18n.t('Moderated Grading')}</div>
        <div className="ModeratedGrading__Container">
          <div className="border border-trbl border-round">
            <label className="ModeratedGrading__CheckboxLabel" htmlFor="assignment_jury_calibrated_grading">
              <input type="hidden" name="jury_calibrated_grading" value={this.state.juryCalibratedGradingChecked} />
              <input
                checked={this.state.juryCalibratedGradingChecked}
                className="Assignment__Checkbox"
                disabled={juryGradingDisabledReason !== null}
                id="assignment_jury_calibrated_grading"
                name="jury_calibrated_grading"
                onChange={this.handleJuryCalibratedGradingChange}
                type="checkbox"
              />
              <strong className="ModeratedGrading__CheckboxLabelText">{I18n.t('Jury-calibrated grading')}</strong>
              {juryGradingDisabledReason && <div className="ModeratedGrading__CheckboxDescription" style={{fontSize: '0.9em'}}>{juryGradingDisabledReason}</div>}
              <div className="ModeratedGrading__CheckboxDescription">
                {I18n.t('Use Jury role rubric scores to calculate final results')}
              </div>
            </label>

            {!this.state.juryCalibratedGradingChecked && (
              <ModeratedGradingCheckbox
                checked={this.state.moderatedGradingChecked}
                gradedSubmissionsExist={this.props.gradedSubmissionsExist}
                isGroupAssignment={this.props.isGroupAssignment}
                isPeerReviewAssignment={this.props.isPeerReviewAssignment}
                onChange={this.handleModeratedGradingChange}
              />
            )}

            {this.state.juryCalibratedGradingChecked && <input type="hidden" name="moderated_grading" value="true" />}

            {this.state.moderatedGradingChecked && !this.state.juryCalibratedGradingChecked && (
              <div className="ModeratedGrading__Content">
                <GraderCountNumberInput
                  currentGraderCount={this.props.currentGraderCount}
                  availableGradersCount={this.props.availableGradersCount}
                  locale={this.props.locale}
                  hideErrors={this.props.hideNumberInputErrors}
                />

                <GraderCommentVisibilityCheckbox
                  checked={this.props.graderCommentsVisibleToGraders}
                  onChange={this.props.onGraderCommentsVisibleToGradersChange}
                />

                <FinalGraderSelectMenu
                  availableModerators={this.props.availableModerators}
                  finalGraderID={this.props.finalGraderID}
                  hideErrors={this.props.hideFinalGraderErrors}
                />

                <GraderNamesVisibleToFinalGraderCheckbox
                  checked={this.props.graderNamesVisibleToFinalGrader}
                />
              </div>
            )}
          </div>
        </div>
      </fieldset>
    )
  }
}
