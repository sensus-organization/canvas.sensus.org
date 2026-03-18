/*
 * Copyright (C) 2025 - present Instructure, Inc.
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

import React, {useState, useEffect, useRef, useMemo, useCallback} from 'react'
import {colors} from '@instructure/canvas-theme'
import {Flex} from '@instructure/ui-flex'
import {Text} from '@instructure/ui-text'
import {View} from '@instructure/ui-view'
import type {RubricRating} from '../types/rubric'

type SliderDisplayProps = {
  ratings: RubricRating[]
  isPreviewMode: boolean
  points: number | undefined
  onPointsChange: (points: number) => void
  maxPoints: number
}

const ACCENT = colors.contrasts.green4570

export const SliderDisplay = React.memo(({
  ratings,
  isPreviewMode,
  points,
  onPointsChange,
  maxPoints,
}: SliderDisplayProps) => {
  const [localValue, setLocalValue] = useState(points ?? 0)
  const localRef = useRef(localValue)
  const dragging = useRef(false)

  useEffect(() => {
    if (!dragging.current) {
      setLocalValue(points ?? 0)
      localRef.current = points ?? 0
    }
  }, [points])

  const commitValue = useCallback(() => {
    dragging.current = false
    onPointsChange(localRef.current)
  }, [onPointsChange])

  const orderedRatings = useMemo(() => {
    return [...ratings].sort((a, b) => a.points - b.points)
  }, [ratings])

  const matchedRating = useMemo(() => {
    if (orderedRatings.length === 0) return undefined
    for (let i = orderedRatings.length - 1; i >= 0; i--) {
      const rating = orderedRatings[i]
      if (i === 0) {
        if (localValue <= rating.points + 0.005) return rating
      } else {
        const prevPoints = orderedRatings[i - 1].points
        if (localValue >= prevPoints + 0.005) return rating
      }
    }
    return undefined
  }, [orderedRatings, localValue])

  const pct = maxPoints > 0 ? (localValue / maxPoints) * 100 : 0

  return (
    <View as="div" data-testid="rubric-assessment-slider-display" padding="small 0 0 0">
      <View as="div" margin="0 0 xx-small 0">
        <Text size="small" weight="bold">
          {localValue.toFixed(2)} / {maxPoints}
        </Text>
        {matchedRating && (
          <Text size="small" color="secondary">
            {' '}&mdash; {matchedRating.description}
          </Text>
        )}
      </View>

      <View as="div" position="relative">
        <input
          type="range"
          min={0}
          max={maxPoints}
          step={0.01}
          value={localValue}
          disabled={isPreviewMode}
          onChange={e => {
            dragging.current = true
            const val = parseFloat(e.target.value)
            localRef.current = val
            setLocalValue(val)
          }}
          onMouseUp={commitValue}
          onTouchEnd={commitValue}
          data-testid="rubric-slider-input"
          style={{
            width: '100%',
            height: '8px',
            appearance: 'none',
            WebkitAppearance: 'none',
            background: `linear-gradient(to right, ${ACCENT} ${pct}%, #e0e0e0 ${pct}%)`,
            borderRadius: '4px',
            outline: 'none',
            cursor: isPreviewMode ? 'default' : 'pointer',
            accentColor: ACCENT,
            margin: 0,
          }}
        />
      </View>

      <View as="div" position="relative" margin="xx-small 0 0 0" height="1.2em">
        {orderedRatings.map((rating: RubricRating, index: number) => {
          const leftPct = maxPoints > 0 ? (rating.points / maxPoints) * 100 : 0
          return (
            <span
              key={`slider-tick-${rating.id ?? index}`}
              style={{
                position: 'absolute',
                left: `${leftPct}%`,
                transform: 'translateX(-50%)',
              }}
            >
              <Text size="x-small" color="secondary">
                {rating.points}
              </Text>
            </span>
          )
        })}
      </View>
    </View>
  )
})
