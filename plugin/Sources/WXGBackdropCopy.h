// Coordinate copy only. TEST9 optical/blur functions remain in WXGGlass.metal.
static const char WXGBackdropCopySource[] =
"\nstruct WXGCopyUniforms { float4 axisX; float4 axisY; float4 origin; };\n"
"kernel void wxgCopyBackdrop(texture2d<float,access::sample> input [[texture(0)]],\n"
" texture2d<float,access::write> output [[texture(1)]],\n"
" constant WXGCopyUniforms &u [[buffer(0)]], uint2 p [[thread_position_in_grid]]) {\n"
" if(p.x>=output.get_width() || p.y>=output.get_height())return;\n"
" constexpr sampler s(coord::normalized,address::clamp_to_edge,filter::linear);\n"
" float2 q=float2(p)+.5;\n"
" float2 uv=u.origin.xy+u.axisX.xy*q.x+u.axisY.xy*q.y;\n"
" output.write(input.sample(s,uv),p);\n"
"}\n";
