import test from 'node:test';
import assert from 'node:assert/strict';
import {palettes,resolveAppearance,contrast} from '../resources/hac-branding/palette.mjs';
test('manual appearance wins and auto respects terminal background hints',()=>{
 assert.equal(resolveAppearance('light','dark','15;0'),'light');
 assert.equal(resolveAppearance('auto','dark','0;15'),'light');
 assert.equal(resolveAppearance('auto','light','15;0'),'dark');
 assert.equal(resolveAppearance('auto','light'),'light');
 assert.equal(resolveAppearance('auto','custom'),'dark');
});
test('body and secondary text have readable contrast on light and dark panels',()=>{
 for(const palette of Object.values(palettes))for(const fg of ['text','muted','dim'])for(const bg of ['background','panel','selected'])assert.ok(contrast(palette[fg],palette[bg])>=4.5,`${fg} on ${bg}`);
 for(const palette of Object.values(palettes))assert.ok(contrast(palette.accent,palette.background)>=4.5);
});
