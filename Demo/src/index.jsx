import React from 'react';
import {registerRoot, Composition, AbsoluteFill, Sequence, Img, staticFile, useCurrentFrame, interpolate} from 'remotion';
import {Audio} from '@remotion/media';
import timeline from '../public/timeline.json';
const ink='#213e33', paper='#f7f5ed', green='#387056';
function Scene({scene}) {
  const f=useCurrentFrame();
  const opacity=interpolate(f,[0,14],[0,1],{extrapolateRight:'clamp'});
  const y=interpolate(f,[0,20],[14,0],{extrapolateRight:'clamp'});
  const settings=scene.id==='model';
  return <AbsoluteFill style={{background:paper,color:ink,fontFamily:'-apple-system, BlinkMacSystemFont, sans-serif',padding:'42px 64px'}}>
    <div style={{display:'flex',justifyContent:'space-between',alignItems:'center',fontSize:23,letterSpacing:2,color:green}}><span>{scene.eyebrow}</span><span style={{letterSpacing:-1,fontWeight:650,fontSize:30}}>Holdfast</span></div>
    <div style={{fontFamily:'Georgia',fontSize:52,marginTop:12,marginBottom:18,opacity,transform:`translateY(${y}px)`}}>{scene.title}</div>
    <div style={{height:1085,display:'flex',alignItems:'center',justifyContent:'center',gap:70}}>
      {settings && <div style={{width:600,fontSize:32,lineHeight:1.6}}><div style={{fontFamily:'Georgia',fontSize:44,marginBottom:20}}>Start on your Mac.</div>LocalMLX is built in.<br/>Or connect a model server.<div style={{fontSize:24,color:'#587164',marginTop:28}}>Choose a model that fits your memory.<br/>Model downloads need extra disk space.</div></div>}
      <Img src={staticFile(scene.id === "undo" && f > scene.durationInFrames * 0.6 ? "restored.png" : scene.image)} style={{maxWidth:settings?900:1790,maxHeight:1085,objectFit:'contain',borderRadius:12,boxShadow:'0 18px 46px #173d2c24',border:'1px solid #c6cfc3',opacity}} />
    </div>
    <div style={{fontSize:27,marginTop:18,display:'flex',alignItems:'center',gap:14}}><span style={{width:9,height:9,borderRadius:9,background:green}}/>{scene.tip}</div>
    <div style={{position:'absolute',bottom:0,left:0,right:0,height:5,background:'#d8e0d4'}}><div style={{height:'100%',background:green,width:`${100*(scene.from+f)/timeline.durationInFrames}%`}}/></div>
    <Sequence from={9}><Audio src={staticFile(scene.audio)}/></Sequence>
  </AbsoluteFill>;
}
function Tour() {
 return <AbsoluteFill>{timeline.scenes.map(s=><Sequence key={s.id} from={s.from} durationInFrames={s.durationInFrames} premountFor={30}><Scene scene={s}/></Sequence>)}<div style={{position:'absolute',bottom:22,right:64,fontFamily:'-apple-system, sans-serif',fontSize:21,color:'#587164'}}>Fictional sample notes · Waiting time removed</div></AbsoluteFill>;
}
registerRoot(()=> <Composition id="HoldfastTour" component={Tour} durationInFrames={timeline.durationInFrames} fps={30} width={1920} height={1440}/>);
